import 'dart:io';

import 'package:flutter/foundation.dart';

/// Linux kiosk audio — route announce MP3/TTS to 3.5mm jack via PulseAudio/ALSA.
class LinuxAudio {
  static Future<bool> playMp3File(String path) async {
    if (!Platform.isLinux) return false;

    final env = _audioEnv();

    for (final cmd in [
      ['paplay', path],
      ['mpg123', '-q', path],
    ]) {
      final which = await Process.run('which', [cmd[0]]);
      if (which.exitCode != 0) continue;
      final r = await Process.run(cmd[0], cmd.sublist(1), environment: env);
      if (r.exitCode == 0) return true;
      debugPrint('qf_tv ${cmd[0]} failed (${r.exitCode}): ${r.stderr}');
    }
    return false;
  }

  static Future<void> speakEspeak(String text) async {
    if (!Platform.isLinux) return;

    // Route via ALSA default (kiosk ~/.asoundrc → pulse) — do NOT pass -a with card index.
    final r = await Process.run(
      'espeak-ng',
      ['-v', 'pt', '-s', '120', text],
      environment: _audioEnv(),
      runInShell: false,
    );
    if (r.exitCode != 0) {
      debugPrint('qf_tv espeak-ng failed (${r.exitCode}): ${r.stderr}');
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
