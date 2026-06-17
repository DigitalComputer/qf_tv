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

    final args = <String>['-v', 'pt', '-s', '120'];
    final device = Platform.environment['QF_ESPEAK_DEVICE'];
    if (device != null && device.isNotEmpty) {
      args.addAll(['-a', device]);
    }
    args.add(text);

    await Process.run('espeak-ng', args, environment: _audioEnv(), runInShell: false);
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
    }
    return env;
  }
}
