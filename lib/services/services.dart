import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

const String kDefaultApiHost = String.fromEnvironment(
  'QF_API_HOST',
  defaultValue: 'https://demo.queueflow.ao',
);

class ConfigService {
  static String? _cachedHost;

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

    _cachedHost = kDefaultApiHost;
    return _cachedHost!;
  }
}

class ApiService {
  ApiService(this.baseUrl);

  final String baseUrl;
  static const _timeout = Duration(seconds: 10);

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
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/api/v1/tv/ping'), headers: _headers())
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<TvDisplay>> getDisplays() async {
    final data = _unwrap(await http
        .get(Uri.parse('$baseUrl/api/v1/tv/displays'), headers: _headers())
        .timeout(_timeout)) as Map<String, dynamic>;

    return (data['displays'] as List)
        .map((e) => TvDisplay.fromJson(e))
        .toList();
  }

  Future<ActivateResult> activate(String displayId) async {
    final data = _unwrap(await http
        .post(
          Uri.parse('$baseUrl/api/v1/tv/displays/$displayId/activate'),
          headers: _headers(),
        )
        .timeout(_timeout)) as Map<String, dynamic>;

    return ActivateResult.fromJson(data);
  }

  Future<QueueState> getQueue(String displayId, String token) async {
    final data = _unwrap(await http
        .get(
          Uri.parse('$baseUrl/api/v1/tv/displays/$displayId/queue'),
          headers: _headers(token),
        )
        .timeout(_timeout)) as Map<String, dynamic>;

    return QueueState.fromJson(data);
  }

  Future<DisplayTemplate> getTemplate(String templateId) async {
    final r = await http
        .get(Uri.parse('$baseUrl/api/v1/tv/templates/$templateId'), headers: _headers())
        .timeout(_timeout);

    if (r.statusCode >= 400) throw HttpException('HTTP ${r.statusCode}');
    return DisplayTemplate.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<({DisplayTemplate template, QueueState queue, ReverbConfig reverb, String tenantId, String branchId})>
      bootstrap(String token) async {
    final data = _unwrap(await http
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

  static Future<void> saveSession(ActivateResult result) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDisplayId, result.displayId);
    await p.setString(_kDisplayName, result.displayName);
    await p.setString(_kToken, result.token);
    await p.setString(_kTemplateId, result.templateId);
    await p.setString(_kBranchId, result.branchId);
    await p.setString(_kTenantId, result.tenantId);
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
