import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'kokoro_service.dart';
import 'linux_audio.dart';
import 'services.dart';
import 'tts_formatter.dart';

/// The call whose audio is currently playing (screen binds to this so the
/// displayed ticket always matches the voice).
class CallingAnnounce {
  final String code;
  final String? counterName;

  const CallingAnnounce({required this.code, this.counterName});
}

/// Portuguese ticket announcements — Kokoro (TV-local) → API MP3 → espeak fallback.
///
/// ALL announces flow through ONE FIFO serial worker ([_enqueue]) so multiple
/// operators calling different filas at the same time NEVER overlap — each
/// senha plays to completion, then the next queued announce plays.
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
  bool? _kokoroReachable;
  DateTime? _lastKokoroProbe;
  static const kokoroReProbeEvery = Duration(seconds: 30);

  /// Gap between announce repeats while a call is active (user: 4s).
  static const repeatPause = Duration(seconds: 4);

  /// FIFO serial announce queue — guarantees one voice at a time.
  final List<Future<void> Function()> _jobQueue = [];
  bool _workerRunning = false;

  /// Per-ticket calling loops (keyed by display code).
  final Map<String, int> _loopGenerations = {};
  final Set<String> _activeLoops = {};

  /// The call whose announce is currently playing. Updated the moment a job
  /// starts speaking; kept during the repeat pause so the screen doesn't
  /// flicker, cleared when its loop stops. Screen binds to this.
  final ValueNotifier<CallingAnnounce?> nowAnnouncing = ValueNotifier(null);

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

  /// Enqueue an announce job on the serial worker and wait for ITS completion.
  Future<void> _enqueue(Future<void> Function() job) {
    final completer = Completer<void>();
    _jobQueue.add(() async {
      try {
        await job();
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    });
    _pumpQueue();
    return completer.future;
  }

  void _pumpQueue() async {
    if (_workerRunning) return;
    _workerRunning = true;
    while (_jobQueue.isNotEmpty) {
      final job = _jobQueue.removeAt(0);
      try {
        await job();
      } catch (e) {
        debugPrint('qf_tv announce job error: $e');
      }
    }
    _workerRunning = false;
  }

  /// Repeat announce every [repeatPause] until [stopCallingLoop] for this code.
  /// Multiple codes can loop concurrently — they interleave through the queue.
  Future<void> startCallingLoop(
    String displayCode, {
    int? counterNumber,
    String? counterName,
    String? counterLabel,
  }) async {
    if (displayCode.isEmpty) return;
    final digits = displayCode.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;

    await init();

    if (_activeLoops.contains(displayCode)) return;
    _activeLoops.add(displayCode);
    final generation = (_loopGenerations[displayCode] ?? 0) + 1;
    _loopGenerations[displayCode] = generation;
    _runCallingLoop(generation, displayCode,
        counterNumber: counterNumber,
        counterName: counterName,
        counterLabel: counterLabel);
  }

  /// Stop the calling loop for [code]. With no code, stop ALL loops + audio.
  Future<void> stopCallingLoop([String? code]) async {
    if (code != null && code.isNotEmpty) {
      _loopGenerations[code] = (_loopGenerations[code] ?? 0) + 1;
      _activeLoops.remove(code);
      if (nowAnnouncing.value?.code == code) {
        nowAnnouncing.value = null;
      }
      return;
    }
    for (final c in _activeLoops.toList()) {
      _loopGenerations[c] = (_loopGenerations[c] ?? 0) + 1;
      _activeLoops.remove(c);
    }
    _jobQueue.clear();
    nowAnnouncing.value = null;
    await stop();
  }

  Future<void> _runCallingLoop(
    int generation,
    String displayCode, {
    int? counterNumber,
    String? counterName,
    String? counterLabel,
  }) async {
    while (
      _activeLoops.contains(displayCode) &&
      _loopGenerations[displayCode] == generation
    ) {
      try {
        // Awaits ITS OWN announce — the serial worker drains other tickets'
        // announces between this ticket's repeats (FIFO, never overlapping).
        await _enqueue(() async {
          // Mark THIS ticket as the one on screen while its audio plays.
          nowAnnouncing.value = CallingAnnounce(
            code: displayCode,
            counterName: counterName,
          );
          await _announce(
            displayCode,
            counterNumber: counterNumber,
            counterLabel: counterLabel,
          );
        });
      } catch (e) {
        debugPrint('qf_tv calling loop announce error: $e');
      }

      if (!_activeLoops.contains(displayCode) ||
          _loopGenerations[displayCode] != generation) {
        break;
      }

      final pauseUntil = DateTime.now().add(repeatPause);
      while (
        _activeLoops.contains(displayCode) &&
        _loopGenerations[displayCode] == generation &&
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

    await _enqueue(() async {
      nowAnnouncing.value = CallingAnnounce(code: displayCode);
      await _announce(displayCode, counterNumber: counterNumber, counterLabel: counterLabel);
    });
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
    nowAnnouncing.value = null;
    for (final c in _activeLoops.toList()) {
      _loopGenerations[c] = (_loopGenerations[c] ?? 0) + 1;
      _activeLoops.remove(c);
    }
    _jobQueue.clear();
    await _player.stop();
    if (Platform.isLinux) {
      if (KokoroService.enabledOnLinux()) {
        await _kokoro.stop();
      }
      await Process.run('pkill', ['-x', 'espeak-ng']);
    }
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
