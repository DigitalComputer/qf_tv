import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

const String kDefaultApiHost = String.fromEnvironment(
  'QF_API_HOST',
  defaultValue: 'https://demo.queueflow.ao',
);

const String kDefaultCentralHost = String.fromEnvironment(
  'QF_CENTRAL_HOST',
  defaultValue: '',
);

class ConfigService {
  static String? _cachedHost;
  static String? _cachedCentralHost;
  static bool? _cachedInsecureSsl;

  static void clearCache() {
    _cachedHost = null;
    _cachedCentralHost = null;
    _cachedInsecureSsl = null;
    ApiHttp.reset();
  }

  static Future<bool> allowInsecureSsl() async {
    if (_cachedInsecureSsl != null) return _cachedInsecureSsl!;

    const fromEnv = bool.fromEnvironment('QF_ALLOW_INSECURE_SSL');
    if (fromEnv) {
      _cachedInsecureSsl = true;
      return true;
    }

    try {
      final file = File('/etc/qf-tv/config.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (json['allow_insecure_ssl'] == true) {
          _cachedInsecureSsl = true;
          return true;
        }
      }
    } catch (_) {}

    _cachedInsecureSsl = false;
    return false;
  }

  static Future<String?> centralHost() async {
    if (_cachedCentralHost != null) return _cachedCentralHost;

    try {
      final file = File('/etc/qf-tv/config.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final host = json['central_host']?.toString();
        if (host != null && host.isNotEmpty) {
          _cachedCentralHost = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
          return _cachedCentralHost;
        }
      }
    } catch (_) {}

    if (kDefaultCentralHost.isNotEmpty) {
      _cachedCentralHost = kDefaultCentralHost;
    }

    return _cachedCentralHost;
  }

  /// Tenant API base URL — never falls back to [centralHost] (central is discovery-only).
  static Future<String> apiHost() async {
    if (_cachedHost != null) return _cachedHost!;

    try {
      final file = File('/etc/qf-tv/config.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final host = json['api_host']?.toString();
        if (host != null && host.isNotEmpty) {
          _cachedHost = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
          return _cachedHost!;
        }
      }
    } catch (_) {}

    final session = await StorageService.getSession();
    final saved = session['api_host'];
    if (saved != null && saved.isNotEmpty) {
      _cachedHost = saved.endsWith('/') ? saved.substring(0, saved.length - 1) : saved;
      return _cachedHost!;
    }

    _cachedHost = kDefaultApiHost;
    return _cachedHost!;
  }

  static Future<bool> usesCentralDiscovery() async {
    final central = await centralHost();
    return central != null && central.isNotEmpty;
  }
}

/// Shared HTTP client — optional TLS bypass for LAN dev (self-signed / hosts file).
class ApiHttp {
  static http.Client? _client;

  static void reset() => _client = null;

  static Future<http.Client> client() async {
    if (_client != null) return _client!;
    if (await ConfigService.allowInsecureSsl()) {
      final io = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      _client = IOClient(io);
    } else {
      _client = http.Client();
    }
    return _client!;
  }

  static Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    return (await client()).get(uri, headers: headers);
  }

  static Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return (await client()).post(uri, headers: headers, body: body);
  }
}

class ApiService {
  ApiService(this.baseUrl);

  final String baseUrl;
  static const _timeout = Duration(seconds: 10);

  /// Strip paths (/dashboard, …) — API base is scheme + host [+ port] only.
  static String normalizeApiBaseUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.contains('://')) {
      s = 'https://$s';
    }
    final uri = Uri.parse(s);
    if (uri.host.isEmpty) return raw.trim();

    final scheme =
        uri.scheme == 'http' || uri.scheme == 'https' ? uri.scheme : 'https';
    final port = uri.hasPort ? uri.port : null;
    if (port != null &&
        !((scheme == 'http' && port == 80) || (scheme == 'https' && port == 443))) {
      return Uri(scheme: scheme, host: uri.host, port: port).toString();
    }
    return '$scheme://${uri.host}';
  }

  /// Try hosts in order — LAN :8000 from config before https URLs from registry.
  static Future<String> resolveReachableHost([String? preferred]) async {
    final config = normalizeApiBaseUrl(await ConfigService.apiHost());
    final primary = normalizeApiBaseUrl(preferred ?? config);
    final candidates = <String>[];

    void add(String? h) {
      if (h == null || h.isEmpty) return;
      final n = normalizeApiBaseUrl(h);
      if (n.isNotEmpty && !candidates.contains(n)) candidates.add(n);
    }

    final configUri = Uri.tryParse(config);
    final primaryUri = Uri.tryParse(primary);

    // /etc/qf-tv says http://tenant:8000 — use before https from central/registry
    if (configUri != null &&
        configUri.scheme == 'http' &&
        configUri.port == 8000) {
      add(config);
      if (primaryUri != null && primaryUri.host == configUri.host) {
        add(_lanHttpFallback(primary));
      }
    }

    add(primary);
    add(_lanHttpFallback(primary));
    if (primary != config) add(config);

    for (final host in candidates) {
      if (await ApiService(host).isReachable()) return host;
    }

    throw Exception('Servidor indisponível ($primary)');
  }

  /// Resolve tenant API host — saved session, registry screen, or config (never central).
  static Future<String> resolveTenantApiHost({
    String? preferred,
    String? displayId,
  }) async {
    if (preferred != null && preferred.isNotEmpty) {
      return resolveReachableHost(preferred);
    }

    final session = await StorageService.getSession();
    final saved = session['api_host'];
    if (saved != null && saved.isNotEmpty) {
      return resolveReachableHost(saved);
    }

    if (displayId != null &&
        displayId.isNotEmpty &&
        await ConfigService.usesCentralDiscovery()) {
      final central = await ConfigService.centralHost();
      if (central != null && central.isNotEmpty) {
        final centralBase = await resolveReachableHost(central);
        final screens =
            await ApiService(centralBase).getScreensFromCentral(centralBase);
        for (final screen in screens) {
          if (screen.id == displayId && screen.apiHost.isNotEmpty) {
            return resolveReachableHost(screen.apiHost);
          }
        }
      }
    }

    return resolveReachableHost(await ConfigService.apiHost());
  }

  static Future<bool> _isCentralHost(String url) async {
    final central = await ConfigService.centralHost();
    if (central == null || central.isEmpty) return false;
    return normalizeApiBaseUrl(url) == normalizeApiBaseUrl(central);
  }

  Future<bool> isReachable() async {
    if (await _isCentralHost(baseUrl)) {
      return pingCentral();
    }
    return ping();
  }

  Map<String, String> _headers([String? token]) => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  dynamic _unwrap(http.Response r) {
    final body = jsonDecode(r.body);
    if (r.statusCode >= 400) {
      if (body is Map) {
        final message = body['message']?.toString();
        if (message != null && message.isNotEmpty) {
          throw HttpException('$message (HTTP ${r.statusCode})');
        }
      }
      throw HttpException('HTTP ${r.statusCode}');
    }
    if (body is Map && body['data'] != null) return body['data'];
    return body;
  }

  Future<bool> pingCentral() async {
    try {
      final r = await ApiHttp
          .get(Uri.parse('$baseUrl/api/v1/tv/screens'), headers: _headers())
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> ping() async {
    if (await _pingUrl(baseUrl)) return true;

    final fallback = _lanHttpFallback(baseUrl);
    if (fallback != null && fallback != baseUrl) {
      return _pingUrl(fallback);
    }

    return false;
  }

  /// Dev/LAN: API on :8000 HTTP while registry returns https://tenant.queueflow.ao
  static String? _lanHttpFallback(String url) {
    final uri = Uri.tryParse(normalizeApiBaseUrl(url));
    if (uri == null || uri.host.isEmpty) return null;
    if (!uri.host.endsWith('.queueflow.ao')) return null;
    if (uri.scheme == 'http' && uri.port == 8000) return null;

    return Uri(
      scheme: 'http',
      host: uri.host,
      port: 8000,
    ).toString();
  }

  Future<bool> _pingUrl(String url) async {
    try {
      final r = await ApiHttp
          .get(Uri.parse('$url/api/v1/tv/ping'), headers: _headers())
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<TvDisplay>> getDisplays() async {
    final data = _unwrap(await ApiHttp
        .get(Uri.parse('$baseUrl/api/v1/tv/displays'), headers: _headers())
        .timeout(_timeout)) as Map<String, dynamic>;

    return (data['displays'] as List)
        .map((e) => TvDisplay.fromJson(e))
        .toList();
  }

  Future<List<TvDisplay>> getScreensFromCentral(String centralHost) async {
    final data = _unwrap(await ApiHttp
        .get(Uri.parse('$centralHost/api/v1/tv/screens'), headers: _headers())
        .timeout(_timeout)) as Map<String, dynamic>;

    return (data['screens'] as List)
        .map((e) => TvDisplay.fromJson(e))
        .toList();
  }

  Future<ActivateResult> activate(String displayId, {List<String>? branchIds}) async {
    final body = branchIds != null && branchIds.isNotEmpty
        ? jsonEncode({'branch_ids': branchIds})
        : null;
    final headers = {
      ..._headers(),
      if (body != null) 'Content-Type': 'application/json',
    };

    final data = _unwrap(await ApiHttp
        .post(
          Uri.parse('$baseUrl/api/v1/tv/displays/$displayId/activate'),
          headers: headers,
          body: body,
        )
        .timeout(_timeout)) as Map<String, dynamic>;

    return ActivateResult.fromJson(data);
  }

  Future<List<TvBranch>> getBranches() async {
    final data = _unwrap(await ApiHttp
        .get(Uri.parse('$baseUrl/api/v1/kiosk/branches'), headers: _headers())
        .timeout(_timeout)) as Map<String, dynamic>;

    return (data['branches'] as List)
        .map((e) => TvBranch.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<QueueState> getQueue(String token) async {
    final data = _unwrap(await ApiHttp
        .get(
          Uri.parse('$baseUrl/api/v1/tv/queue'),
          headers: _headers(token),
        )
        .timeout(_timeout)) as Map<String, dynamic>;

    return QueueState.fromJson(data);
  }

  Future<DisplayConfig> getDisplayConfig(String token) async {
    final data = _unwrap(await ApiHttp
        .get(
          Uri.parse('$baseUrl/api/v1/display/config'),
          headers: _headers(token),
        )
        .timeout(_timeout)) as Map<String, dynamic>;

    return DisplayConfig.fromJson(data);
  }

  Future<DisplayState> getDisplayState(String token) async {
    final data = _unwrap(await ApiHttp
        .get(
          Uri.parse('$baseUrl/api/v1/display/state'),
          headers: _headers(token),
        )
        .timeout(_timeout)) as Map<String, dynamic>;

    return DisplayState.fromJson(data);
  }

  Future<List<int>> fetchAnnounceAudio(
    String token,
    String code, {
    int? counter,
  }) async {
    final params = {'code': code};
    if (counter != null) params['counter'] = counter.toString();

    final uri = Uri.parse('$baseUrl/api/v1/display/announce').replace(
      queryParameters: params,
    );

    final r = await ApiHttp
        .get(uri, headers: {
          ..._headers(token),
          'Accept': 'audio/mpeg',
        })
        .timeout(const Duration(seconds: 30));

    if (r.statusCode >= 400) {
      throw HttpException('announce HTTP ${r.statusCode}');
    }

    return r.bodyBytes;
  }

  Future<DisplayTemplate> getTemplate(String templateId) async {
    final r = await ApiHttp
        .get(Uri.parse('$baseUrl/api/v1/tv/templates/$templateId'), headers: _headers())
        .timeout(_timeout);

    if (r.statusCode >= 400) throw HttpException('HTTP ${r.statusCode}');
    return DisplayTemplate.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<({DisplayTemplate template, QueueState queue, ReverbConfig reverb, String tenantId, String branchId, List<String> branchIds, String displayId, String apiHost})>
      bootstrap(String token) async {
    final data = _unwrap(await ApiHttp
        .get(Uri.parse('$baseUrl/api/v1/tv/bootstrap'), headers: _headers(token))
        .timeout(_timeout)) as Map<String, dynamic>;

    final rawIds = data['branch_ids'] as List? ?? [];
    final branchIds = rawIds.map((e) => e.toString()).toList();

    return (
      template: DisplayTemplate.fromJson(data['template']),
      queue: QueueState.fromJson(data['queue']),
      reverb: ReverbConfig.fromJson(data['reverb']),
      tenantId: data['tenant_id']?.toString() ?? '',
      branchId: data['branch_id']?.toString() ?? '',
      branchIds: branchIds,
      displayId: data['display_id']?.toString() ?? '',
      apiHost: data['api_host']?.toString() ?? '',
    );
  }
}

class StorageService {
  static const _kDisplayId = 'display_id';
  static const _kDisplayName = 'display_name';
  static const _kToken = 'display_token';
  static const _kTemplateId = 'template_id';
  static const _kBranchId = 'branch_id';
  static const _kBranchIds = 'branch_ids';
  static const _kTenantId = 'tenant_id';
  static const _kApiHost = 'api_host';

  static Future<void> saveSession(ActivateResult result) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDisplayId, result.displayId);
    await p.setString(_kDisplayName, result.displayName);
    await p.setString(_kToken, result.token);
    await p.setString(_kTemplateId, result.templateId);
    await p.setString(_kBranchId, result.branchId);
    if (result.branchIds.isNotEmpty) {
      await p.setStringList(_kBranchIds, result.branchIds);
    } else {
      await p.remove(_kBranchIds);
    }
    await p.setString(_kTenantId, result.tenantId);
    if (result.apiHost.isNotEmpty) {
      await p.setString(_kApiHost, result.apiHost);
    }
  }

  static Future<Map<String, String?>> getSession() async {
    final p = await SharedPreferences.getInstance();
    return {
      'display_id': p.getString(_kDisplayId),
      'display_name': p.getString(_kDisplayName),
      'token': p.getString(_kToken),
      'template_id': p.getString(_kTemplateId),
      'branch_id': p.getString(_kBranchId),
      'branch_ids': p.getStringList(_kBranchIds)?.join(','),
      'tenant_id': p.getString(_kTenantId),
      'api_host': p.getString(_kApiHost),
    };
  }

  static Future<void> clearSession() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kDisplayId);
    await p.remove(_kDisplayName);
    await p.remove(_kToken);
    await p.remove(_kTemplateId);
    await p.remove(_kBranchId);
    await p.remove(_kBranchIds);
    await p.remove(_kTenantId);
    await p.remove(_kApiHost);
  }
}

