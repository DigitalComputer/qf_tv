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

  static Future<bool> usesCentralDiscovery() async {
    final central = await centralHost();
    return central != null && central.isNotEmpty;
  }

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

    final central = await centralHost();
    if (central != null && central.isNotEmpty) {
      _cachedHost = central;
      return _cachedHost!;
    }

    _cachedHost = kDefaultApiHost;
    return _cachedHost!;
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

  /// Prefer config host; on LAN fall back to http://tenant.queueflow.ao:8000.
  static Future<String> resolveReachableHost([String? preferred]) async {
    final host = preferred ?? await ConfigService.apiHost();
    if (await ApiService(host).ping()) return host;

    final fallback = _lanHttpFallback(host);
    if (fallback != null && fallback != host && await ApiService(fallback).ping()) {
      return fallback;
    }

    throw Exception('Servidor indisponível ($host)');
  }

  Map<String, String> _headers([String? token]) => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  dynamic _unwrap(http.Response r) {
    if (r.statusCode >= 400) {
      throw HttpException('HTTP ${r.statusCode}');
    }
    final body = jsonDecode(r.body);
    if (body is Map && body['data'] != null) return body['data'];
    return body;
  }

  Future<bool> ping() async {
    if (await _pingUrl(baseUrl)) return true;

    final fallback = _lanHttpFallback(baseUrl);
    if (fallback != null && fallback != baseUrl) {
      return _pingUrl(fallback);
    }

    return false;
  }

  /// Dev/LAN: API on :8000 HTTP while config says https://tenant.queueflow.ao
  static String? _lanHttpFallback(String url) {
    final uri = Uri.tryParse(url);
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

  Future<ActivateResult> activate(String displayId) async {
    final data = _unwrap(await ApiHttp
        .post(
          Uri.parse('$baseUrl/api/v1/tv/displays/$displayId/activate'),
          headers: _headers(),
        )
        .timeout(_timeout)) as Map<String, dynamic>;

    return ActivateResult.fromJson(data);
  }

  Future<QueueState> getQueue(String displayId, String token) async {
    final data = _unwrap(await ApiHttp
        .get(
          Uri.parse('$baseUrl/api/v1/tv/displays/$displayId/queue'),
          headers: _headers(token),
        )
        .timeout(_timeout)) as Map<String, dynamic>;

    return QueueState.fromJson(data);
  }

  Future<DisplayTemplate> getTemplate(String templateId) async {
    final r = await ApiHttp
        .get(Uri.parse('$baseUrl/api/v1/tv/templates/$templateId'), headers: _headers())
        .timeout(_timeout);

    if (r.statusCode >= 400) throw HttpException('HTTP ${r.statusCode}');
    return DisplayTemplate.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<({DisplayTemplate template, QueueState queue, ReverbConfig reverb, String tenantId, String branchId})>
      bootstrap(String token) async {
    final data = _unwrap(await ApiHttp
        .get(Uri.parse('$baseUrl/api/v1/tv/bootstrap'), headers: _headers(token))
        .timeout(_timeout)) as Map<String, dynamic>;

    return (
      template: DisplayTemplate.fromJson(data['template']),
      queue: QueueState.fromJson(data['queue']),
      reverb: ReverbConfig.fromJson(data['reverb']),
      tenantId: data['tenant_id']?.toString() ?? '',
      branchId: data['branch_id']?.toString() ?? '',
    );
  }
}

class StorageService {
  static const _kDisplayId = 'display_id';
  static const _kDisplayName = 'display_name';
  static const _kToken = 'display_token';
  static const _kTemplateId = 'template_id';
  static const _kBranchId = 'branch_id';
  static const _kTenantId = 'tenant_id';
  static const _kApiHost = 'api_host';

  static Future<void> saveSession(ActivateResult result) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDisplayId, result.displayId);
    await p.setString(_kDisplayName, result.displayName);
    await p.setString(_kToken, result.token);
    await p.setString(_kTemplateId, result.templateId);
    await p.setString(_kBranchId, result.branchId);
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
    await p.remove(_kTenantId);
    await p.remove(_kApiHost);
  }
}

typedef ReverbEventCallback = void Function();

class ReverbService {
  ReverbService({
    required this.config,
    required this.tenantId,
    required this.branchId,
    required this.onEvent,
    required this.onConnectionChange,
  });

  final ReverbConfig config;
  final String tenantId;
  final String branchId;
  final ReverbEventCallback onEvent;
  final void Function(bool connected) onConnectionChange;

  Timer? _pollTimer;
  bool _disposed = false;

  void connect() {
    _startPolling();
    onConnectionChange(true);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!_disposed) onEvent();
    });
  }

  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    onConnectionChange(false);
  }
}
