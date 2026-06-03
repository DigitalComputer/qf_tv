import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Portuguese ticket announcements (aligned with qf_screen TTS).
class AnnounceService {
  AnnounceService() : _tts = FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;
  bool _speaking = false;
  final List<Future<void> Function()> _queue = [];

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
    await _tts.setLanguage('pt-PT');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(0.9);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  Future<void> announceTicket(String displayCode, {String? counterLabel}) async {
    if (displayCode.isEmpty) return;
    await init();

    _queue.add(() => _speakTicket(displayCode, counterLabel: counterLabel));
    if (!_speaking) {
      await _drainQueue();
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

  Future<void> _speakTicket(String code, {String? counterLabel}) async {
    await _speak('Atenção.');
    await _speak('Senha. ${_spellCode(code)}.');
    await _speak(_spellCode(code));
    if (counterLabel != null && counterLabel.isNotEmpty) {
      await _speak('Por favor, dirija-se ao $counterLabel.');
    }
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  String _spellCode(String code) {
    return code.split('').map((c) => _digitPt[c] ?? c).join('  ');
  }

  static String? counterNumberFromName(String? counterName) {
    if (counterName == null || counterName.isEmpty) return null;
    final match = RegExp(r'\d+').firstMatch(counterName);
    return match?.group(0);
  }

  static String counterPhrase(String? counterName) {
    if (counterName == null || counterName.isEmpty) {
      return 'balcão';
    }
    final numStr = counterNumberFromName(counterName);
    if (numStr != null) {
      final n = int.tryParse(numStr);
      if (n != null) {
        return 'balcão número ${_numberPt(n)}';
      }
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
    _queue.clear();
    await _tts.stop();
    _speaking = false;
  }
}
