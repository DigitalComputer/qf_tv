import 'dart:io';

import 'package:flutter/foundation.dart';

/// Linux kiosk audio — route announce MP3/TTS to 3.5mm jack via PulseAudio/ALSA.
class LinuxAudio {
  /// Play MP3/WAV via paplay (same Pulse sink as v1.0.17 kiosk audio fix).
  static Future<bool> playAudioFile(String path) async {
    if (!Platform.isLinux) return false;

    final env = _audioEnv();
    final sink = Platform.environment['QF_PULSE_SINK'];
    final alsa = Platform.environment['QF_ALSA_DEVICE'];
    final isMp3 = path.toLowerCase().endsWith('.mp3');

    final attempts = <List<String>>[];
    if (sink != null && sink.isNotEmpty) {
      attempts.add(['paplay', '--device=$sink', path]);
    }
    attempts.addAll([
      ['paplay', path],
      ['pw-play', path],
    ]);
    if (isMp3) {
      attempts.addAll([
        ['mpg123', '-q', '-o', 'pulse', path],
        ['mpg123', '-q', '-a', env['AUDIODEV'] ?? 'default', path],
      ]);
      if (alsa != null && alsa.isNotEmpty) {
        attempts.add(['mpg123', '-q', '-a', alsa, path]);
      }
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

  static Future<bool> playMp3File(String path) => playAudioFile(path);

  /// Local TTS fallback — pt-PT espeak-ng rendered to WAV, played via paplay.
  static Future<void> speakEspeak(String text) async {
    if (!Platform.isLinux) return;

    final env = _audioEnv();
    final wav =
        '${Directory.systemTemp.path}/qf_tv_tts_${DateTime.now().millisecondsSinceEpoch}.wav';

    try {
      var r = await Process.run(
        'espeak-ng',
        ['-v', 'pt-pt', '-s', '110', '-p', '48', '-w', wav, text],
        environment: env,
        runInShell: false,
      );
      if (r.exitCode == 0 && await File(wav).exists()) {
        if (await playAudioFile(wav)) return;
        debugPrint('qf_tv espeak paplay failed (${r.exitCode})');
      } else {
        debugPrint('qf_tv espeak-ng wav failed (${r.exitCode}): ${r.stderr}');
      }

      // Last resort: direct ALSA (no paplay).
      final alsa = Platform.environment['QF_ALSA_DEVICE'];
      final args = ['-v', 'pt-pt', '-s', '110', '-p', '48', text];
      r = await Process.run('espeak-ng', args, environment: env, runInShell: false);
      if (r.exitCode == 0) return;

      if (alsa != null && alsa.isNotEmpty) {
        r = await Process.run(
          'espeak-ng',
          [...args, '-a', alsa],
          environment: env,
          runInShell: false,
        );
        if (r.exitCode != 0) {
          debugPrint('qf_tv espeak-ng alsa failed (${r.exitCode}): ${r.stderr}');
        }
      }
    } finally {
      final f = File(wav);
      if (await f.exists()) await f.delete();
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
