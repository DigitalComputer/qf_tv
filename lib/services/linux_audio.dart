import 'dart:io';

import 'package:flutter/foundation.dart';

/// Linux kiosk audio — route announce MP3/TTS to 3.5mm jack via PulseAudio/ALSA.
class LinuxAudio {
  static Future<bool> playMp3File(String path) async {
    if (!Platform.isLinux) return false;

    final env = _audioEnv();
    final sink = Platform.environment['QF_PULSE_SINK'];
    final alsa = Platform.environment['QF_ALSA_DEVICE'];

    final attempts = <List<String>>[];
    if (sink != null && sink.isNotEmpty) {
      attempts.add(['paplay', '--device=$sink', path]);
    }
    attempts.addAll([
      ['paplay', path],
      ['pw-play', path],
      ['mpg123', '-q', '-o', 'pulse', path],
      ['mpg123', '-q', '-a', env['AUDIODEV'] ?? 'default', path],
    ]);
    if (alsa != null && alsa.isNotEmpty) {
      attempts.add(['mpg123', '-q', '-a', alsa, path]);
    }

    for (final cmd in attempts) {
      final bin = cmd[0];
      final which = await Process.run('which', [bin]);
      if (which.exitCode != 0) continue;
      final r = await Process.run(bin, cmd.sublist(1), environment: env);
      if (r.exitCode == 0) {
        debugPrint('qf_tv audio: $bin ok');
        return true;
      }
      debugPrint('qf_tv $bin failed (${r.exitCode}): ${r.stderr}');
    }
    return false;
  }

  static Future<void> speakEspeak(String text) async {
    if (!Platform.isLinux) return;

    final env = _audioEnv();
    final alsa = Platform.environment['QF_ALSA_DEVICE'];

    // Route via ALSA default (kiosk ~/.asoundrc → pulse) — do NOT pass -a with card index.
    var r = await Process.run(
      'espeak-ng',
      ['-v', 'pt', '-s', '120', text],
      environment: env,
      runInShell: false,
    );
    if (r.exitCode == 0) return;

    debugPrint('qf_tv espeak-ng default failed (${r.exitCode}): ${r.stderr}');

    // Direct ALSA hardware fallback when PulseAudio is down.
    if (alsa != null && alsa.isNotEmpty) {
      r = await Process.run(
        'espeak-ng',
        ['-v', 'pt', '-s', '120', '-a', alsa, text],
        environment: env,
        runInShell: false,
      );
      if (r.exitCode != 0) {
        debugPrint('qf_tv espeak-ng alsa failed (${r.exitCode}): ${r.stderr}');
      }
    }
  }

  static Map<String, String> _audioEnv() {
    final env = Map<String, String>.from(Platform.environment);
    final sink = Platform.environment['QF_PULSE_SINK'];
    if (sink != null && sink.isNotEmpty) {
      env['PULSE_SINK'] = sink;
    }
    final alsa = Platform.environment['QF_ALSA_DEVICE'];
    if (alsa != null && alsa.isNotEmpty) {
      env['AUDIODEV'] = alsa;
    } else {
      env.putIfAbsent('AUDIODEV', () => 'default');
    }
    return env;
  }
}
