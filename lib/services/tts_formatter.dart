/// Portuguese ticket announcement text — matches Laravel DisplayAnnounceService.
class TtsFormatter {
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

  /// Full announce phrase for Kokoro / edge-tts.
  /// Format: `Senha <code>, dirija-se ao balcão <n>.` (code spoken letter-by-letter).
  static String ticketAnnouncement(String displayCode, {int? counterNumber}) {
    final spelled = spellCode(displayCode);
    if (counterNumber == null) {
      return 'Senha $spelled.';
    }
    return 'Senha $spelled, dirija-se ao balcão ${numberPt(counterNumber)}.';
  }

  /// Same, but takes a ready-made counter label (e.g. "balcão número um").
  /// Used when only the counter name is known (payload may lack a number).
  static String ticketAnnouncementWithLabel(String displayCode, {String? counterLabel}) {
    final spelled = spellCode(displayCode);
    final label = counterLabel?.trim();
    if (label == null || label.isEmpty) {
      return 'Senha $spelled.';
    }
    return 'Senha $spelled, dirija-se ao $label.';
  }

  static String spellCode(String code) {
    return code.split('').map((c) => _digitPt[c] ?? c).join(' ');
  }

  static String numberPt(int n) {
    if (n < 20) return _onesPt[n];
    final t = n ~/ 10;
    final u = n % 10;
    if (u == 0) return _tensPt[t];
    return '${_tensPt[t]} e ${_onesPt[u]}';
  }
}
