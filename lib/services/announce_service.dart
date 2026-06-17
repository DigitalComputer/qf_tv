import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'linux_audio.dart';
import 'services.dart';

/// Portuguese ticket announcements — API neural MP3 (same as qf_screen) + espeak fallback.
class AnnounceService {
  AnnounceService({required ApiService api, required String token})
      : _api = api,
        _token = token;

  final ApiService _api;
  final String _token;
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  bool _speaking = false;
  final List<Future<void> Function()> _queue = [];

  /// Gap between announce plays while call active (matches qf_screen poll interval).
  static const repeatPause = Duration(seconds: 10);

  bool _callingLoopActive = false;
  String? _callingLoopCode;
  int? _callingLoopCounterNumber;
  String? _callingLoopCounterLabel;
  int _callingLoopGeneration = 0;

  static const _digitPt = {
    '0': 'zero',
    '1': 'um',
    '2': 'dois',
    '3': 'três',
    '4': 'quatro',
    '5': 'cinco',
    '6': 'seis',
    '7': 'sete',
    '8': 'oito',
    '9': 'nove',
  };

  static const _tensPt = [
    '',
    '',
    'vinte',
    'trinta',
    'quarenta',
    'cinquenta',
    'sessenta',
    'setenta',
    'oitenta',
    'noventa',
  ];

  static const _onesPt = [
    'zero',
    'um',
    'dois',
    'três',
    'quatro',
    'cinco',
    'seis',
    'sete',
    'oito',
    'nove',
    'dez',
    'onze',
    'doze',
    'treze',
    'catorze',
    'quinze',
    'dezasseis',
    'dezassete',
    'dezoito',
    'dezanove',
  ];

  Future<void> init() async {
    if (_ready) return;
    await _player.setReleaseMode(ReleaseMode.stop);
    if (Platform.isLinux) {
      final which = await Process.run('which', ['espeak-ng']);
      if (which.exitCode != 0) {
        debugPrint('qf_tv TTS: espeak-ng not installed (offline fallback) — apt install espeak-ng');
      }
    }
    _ready = true;
  }

  static bool _isValidMp3(List<int> bytes) {
    if (bytes.length < 128) return false;
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) return true; // ID3
    return bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0; // MPEG sync
  }

  /// Repeat neural/espeak announce every [repeatPause] until [stopCallingLoop].
  Future<void> startCallingLoop(
    String displayCode, {
    int? counterNumber,
    String? counterLabel,
  }) async {
    if (displayCode.isEmpty) return;
    final digits = displayCode.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;

    await init();

    if (_callingLoopActive && _callingLoopCode == displayCode) return;

    await stopCallingLoop();

    _callingLoopCode = displayCode;
    _callingLoopCounterNumber = counterNumber;
    _callingLoopCounterLabel = counterLabel;
    _callingLoopActive = true;
    final generation = ++_callingLoopGeneration;
    _runCallingLoop(generation);
  }

  Future<void> stopCallingLoop() async {
    _callingLoopGeneration++;
    _callingLoopActive = false;
    _callingLoopCode = null;
    _callingLoopCounterNumber = null;
    _callingLoopCounterLabel = null;
    await stop();
  }

  Future<void> _runCallingLoop(int generation) async {
    while (
      _callingLoopActive &&
      generation == _callingLoopGeneration &&
      _callingLoopCode != null
    ) {
      final code = _callingLoopCode!;
      final counterNumber = _callingLoopCounterNumber;
      final counterLabel = _callingLoopCounterLabel;

      try {
        await _announce(
          code,
          counterNumber: counterNumber,
          counterLabel: counterLabel,
        );
      } catch (e) {
        debugPrint('qf_tv calling loop announce error: $e');
      }

      if (!_callingLoopActive || generation != _callingLoopGeneration) break;

      final pauseUntil = DateTime.now().add(repeatPause);
      while (
        _callingLoopActive &&
        generation == _callingLoopGeneration &&
        DateTime.now().isBefore(pauseUntil)
      ) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  Future<void> announceTicket(
    String displayCode, {
    int? counterNumber,
    String? counterLabel,
  }) async {
    if (displayCode.isEmpty) return;
    final digits = displayCode.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;

    await init();

    _queue.add(() => _announce(displayCode, counterNumber: counterNumber, counterLabel: counterLabel));
    if (!_speaking) {
      await _drainQueue();
    }
  }

  Future<void> _announce(
    String code, {
    int? counterNumber,
    String? counterLabel,
  }) async {
    try {
      final bytes = await _api.fetchAnnounceAudio(_token, code, counter: counterNumber);
      if (!_isValidMp3(bytes)) {
        throw FormatException('announce response not MP3 (${bytes.length} bytes)');
      }
      if (await _playBytes(bytes)) return;
      debugPrint('qf_tv neural MP3 playback failed — espeak fallback');
    } catch (e) {
      debugPrint('qf_tv API announce failed — espeak fallback: $e');
    }

    await _speakTicketEspeak(code, counterLabel: counterLabel);
  }

  Future<bool> _playBytes(List<int> bytes) async {
    // Linux kiosk: paplay/mpg123 via launcher env — audioplayers/GStreamer often silent.
    if (Platform.isLinux) {
      final tmp = File(
        '${Directory.systemTemp.path}/qf_tv_announce_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      try {
        await tmp.writeAsBytes(bytes);
        if (await LinuxAudio.playMp3File(tmp.path)) return true;
        debugPrint('qf_tv system MP3 failed, trying audioplayers');
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
    }

    await _player.stop();
    try {
      await _player.play(BytesSource(Uint8List.fromList(bytes)), volume: 1.0);
      await _player.onPlayerComplete.first;
      return true;
    } catch (e) {
      debugPrint('qf_tv audioplayers failed: $e');
      if (!Platform.isLinux) rethrow;
      return false;
    }
  }

  Future<void> _drainQueue() async {
    if (_speaking) return;
    _speaking = true;
    while (_queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      try {
        await job();
      } catch (e) {
        debugPrint('qf_tv TTS error: $e');
      }
    }
    _speaking = false;
  }

  Future<void> _speakTicketEspeak(String code, {String? counterLabel}) async {
    await _speakEspeak('Atenção.');
    await _speakEspeak('Senha. ${_spellCode(code)}.');
    await _speakEspeak(_spellCode(code));
    if (counterLabel != null && counterLabel.isNotEmpty) {
      await _speakEspeak('Por favor, dirija-se ao $counterLabel.');
    }
  }

  Future<void> _speakEspeak(String text) async {
    if (!Platform.isLinux) return;
    await LinuxAudio.speakEspeak(text);
  }

  String _spellCode(String code) {
    return code.split('').map((c) => _digitPt[c] ?? c).join('  ');
  }

  static int? counterNumberFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final raw = payload['counter_number'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return counterNumberFromName(payload['counter_name']?.toString());
  }

  static int? counterNumberFromName(String? counterName) {
    if (counterName == null || counterName.isEmpty) return null;
    final match = RegExp(r'\d+').firstMatch(counterName);
    return int.tryParse(match?.group(0) ?? '');
  }

  static String counterPhrase(String? counterName) {
    if (counterName == null || counterName.isEmpty) {
      return 'balcão';
    }
    final numStr = counterNumberFromName(counterName);
    if (numStr != null) {
      return 'balcão número ${_numberPt(numStr)}';
    }
    return counterName;
  }

  static String _numberPt(int n) {
    if (n < 20) return _onesPt[n];
    final t = n ~/ 10;
    final u = n % 10;
    if (u == 0) return _tensPt[t];
    return '${_tensPt[t]} e ${_onesPt[u]}';
  }

  Future<void> stop() async {
    _callingLoopGeneration++;
    _callingLoopActive = false;
    _queue.clear();
    await _player.stop();
    if (Platform.isLinux) {
      await Process.run('pkill', ['-x', 'espeak-ng']);
    }
    _speaking = false;
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
