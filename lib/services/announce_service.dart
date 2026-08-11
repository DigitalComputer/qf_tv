import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'kokoro_service.dart';
import 'linux_audio.dart';
import 'services.dart';
import 'tts_formatter.dart';

/// Portuguese ticket announcements — Kokoro (TV-local) → API MP3 → espeak fallback.
class AnnounceService {
  AnnounceService({required ApiService api, required String token})
      : _api = api,
        _token = token,
        _kokoro = KokoroService();

  final ApiService _api;
  final String _token;
  final KokoroService _kokoro;
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  bool _speaking = false;
  bool? _kokoroReachable;
  DateTime? _lastKokoroProbe;
  static const kokoroReProbeEvery = Duration(seconds: 30);
  final List<Future<void> Function()> _queue = [];

  /// Gap between announce plays while call active. User wants snappy repeat
  /// (~2s), not the old 10s — combined with a ~5s phrase this yields a
  /// repeat roughly every 7s instead of the previous 60s+ kokoro wait.
  static const repeatPause = Duration(seconds: 2);

  bool _callingLoopActive = false;
  String? _callingLoopCode;
  int? _callingLoopCounterNumber;
  String? _callingLoopCounterLabel;
  int _callingLoopGeneration = 0;

  Future<void> init() async {
    if (_ready) return;
    await _player.setReleaseMode(ReleaseMode.stop);
    if (Platform.isLinux) {
      final which = await Process.run('which', ['espeak-ng']);
      if (which.exitCode != 0) {
        debugPrint('qf_tv TTS: espeak-ng not installed (offline fallback) — apt install espeak-ng');
      }
      if (KokoroService.enabledOnLinux()) {
        _kokoroReachable = await _kokoro.isReachable();
        debugPrint('qf_tv Kokoro TTS: ${_kokoroReachable == true ? KokoroService.kokoroTtsUrl() : 'unreachable'}');
      }
    }
    _ready = true;
  }

  static bool _isValidMp3(List<int> bytes) {
    if (bytes.length < 128) return false;
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) return true; // ID3
    return bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0; // MPEG sync
  }

  /// Repeat announce every [repeatPause] until [stopCallingLoop].
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
    // 1) Fast path: server neural MP3 (edge-tts, cached) — ~2-5s, zero local
    // CPU load. Was previously the 3rd fallback behind local Kokoro whose
    // inference takes 30-120s on the weak box CPU and froze the UI.
    try {
      final bytes = await _api
          .fetchAnnounceAudio(_token, code, counter: counterNumber, counterLabel: counterLabel)
          .timeout(const Duration(seconds: 20));
      if (_isValidMp3(bytes) && await _playBytes(bytes)) return;
      debugPrint('qf_tv API MP3 unplayable — Kokoro fallback');
    } catch (e) {
      debugPrint('qf_tv API MP3 failed — Kokoro fallback: $e');
    }

    // 2) Local Kokoro TTS (natural pt-BR, offline).
    if (Platform.isLinux && KokoroService.enabledOnLinux()) {
      _kokoroReachable ??= await _kokoro.isReachable();
      // A transient outage (e.g. TTS service restarting, corrupt model being
      // re-downloaded) disables Kokoro for the whole session otherwise.
      if (_kokoroReachable == false) {
        final now = DateTime.now();
        if (_lastKokoroProbe == null ||
            now.difference(_lastKokoroProbe!) >= kokoroReProbeEvery) {
          _lastKokoroProbe = now;
          _kokoroReachable = await _kokoro.isReachable();
        }
      }
      if (_kokoroReachable == true) {
        final text = TtsFormatter.ticketAnnouncementWithLabel(
          code,
          counterLabel: counterLabel ?? counterPhrase(null),
        );
        if (await _kokoro.speak(text)) return;
        debugPrint('qf_tv Kokoro speak failed — espeak fallback');
        // Model/service broken (e.g. corrupt ONNX): stop retrying every
        // announce — degrades to espeak, not per-call 300MB reload.
        // Re-probe kicks in after [kokoroReProbeEvery].
        _kokoroReachable = false;
        _lastKokoroProbe = DateTime.now();
      }
    }

    // 3) Last resort: espeak.
    await _speakTicketEspeak(code, counterLabel: counterLabel);
  }

  Future<bool> _playBytes(List<int> bytes) async {
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
    await _speakEspeak('Senha. ${TtsFormatter.spellCode(code)}.');
    if (counterLabel != null && counterLabel.isNotEmpty) {
      await _speakEspeak('Dirija-se ao $counterLabel.');
    }
  }

  Future<void> _speakEspeak(String text) async {
    if (!Platform.isLinux) return;
    await LinuxAudio.speakEspeak(text);
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
      return 'balcão número ${TtsFormatter.numberPt(numStr)}';
    }
    return counterName;
  }

  Future<void> stop() async {
    _callingLoopGeneration++;
    _callingLoopActive = false;
    _queue.clear();
    await _player.stop();
    if (Platform.isLinux) {
      if (KokoroService.enabledOnLinux()) {
        await _kokoro.stop();
      }
      await Process.run('pkill', ['-x', 'espeak-ng']);
    }
    _speaking = false;
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
