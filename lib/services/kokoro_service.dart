import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Local Kokoro TTS on TV box (127.0.0.1:5050) — natural pt-BR voice.
class KokoroService {
  KokoroService({String? baseUrl}) : _baseUrl = (baseUrl ?? kokoroTtsUrl()).replaceAll(RegExp(r'/$'), '');

  final String _baseUrl;

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
  ///
  /// Engine /speak is async (returns on submit); we poll /status until the
  /// worker finishes. Budget is generous (180s) — the box CPU is slow under
  /// load and synthesis alone can take tens of seconds. Previously a 60s
  /// HTTP timeout killed long calls mid-play and degraded to espeak.
  Future<bool> speak(String text) async {
    if (text.trim().isEmpty) return false;
    try {
      final r = await http
          .post(
            Uri.parse('$_baseUrl/speak'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode < 200 || r.statusCode >= 300) {
        debugPrint('qf_tv Kokoro TTS submit HTTP ${r.statusCode}: ${r.body}');
        return false;
      }
      final deadline = DateTime.now().add(const Duration(seconds: 180));
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 500));
        final s = await http
            .get(Uri.parse('$_baseUrl/status'))
            .timeout(const Duration(seconds: 3));
        if (s.statusCode == 200) {
          final body = jsonDecode(s.body) as Map<String, dynamic>;
          if (body['busy'] != true) {
            debugPrint('qf_tv Kokoro TTS ok');
            return true;
          }
        }
      }
      debugPrint('qf_tv Kokoro TTS timed out waiting for playback');
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
