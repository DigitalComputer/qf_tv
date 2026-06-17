import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Local Kokoro TTS on TV box (127.0.0.1:5050) — natural pt-BR voice.
class KokoroService {
  KokoroService({String? baseUrl}) : _baseUrl = (baseUrl ?? kokoroTtsUrl()).replaceAll(RegExp(r'/$'), '');

  final String _baseUrl;
  static const _timeout = Duration(seconds: 60);

  static String kokoroTtsUrl() {
    const fromEnv = String.fromEnvironment('KOKORO_TTS_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    final runtime = Platform.environment['KOKORO_TTS_URL'];
    if (runtime != null && runtime.isNotEmpty) return runtime;
    return 'http://127.0.0.1:5050';
  }

  static bool enabledOnLinux() {
    if (!Platform.isLinux) return false;
    final flag = Platform.environment['QF_TV_KOKORO'];
    if (flag == '0' || flag == 'false') return false;
    return true;
  }

  Future<bool> isReachable() async {
    try {
      final r = await http.get(Uri.parse('$_baseUrl/health')).timeout(const Duration(seconds: 2));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Blocking speak — Kokoro plays audio locally on TV hardware.
  Future<bool> speak(String text) async {
    if (text.trim().isEmpty) return false;
    try {
      final r = await http
          .post(
            Uri.parse('$_baseUrl/speak'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(_timeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        debugPrint('qf_tv Kokoro TTS ok');
        return true;
      }
      debugPrint('qf_tv Kokoro TTS HTTP ${r.statusCode}: ${r.body}');
    } catch (e) {
      debugPrint('qf_tv Kokoro TTS failed: $e');
    }
    return false;
  }

  Future<void> stop() async {
    try {
      await http.post(Uri.parse('$_baseUrl/stop')).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}
