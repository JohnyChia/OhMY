abstract final class ProfanityFilter {
  static const _blockedWords = <String>{
    'ass',
    'arse',
    'arsehole',
    'asshole',
    'bastard',
    'bitch',
    'bish',
    'bytch',
    'bullshit',
    'cb',
    'ccb',
    'cock',
    'crap',
    'cum',
    'cunt',
    'dick',
    'dickhead',
    'fag',
    'faggot',
    'fcuk',
    'fck',
    'fuck',
    'fucked',
    'fucker',
    'fucking',
    'fuk',
    'phuck',
    'jizz',
    'mf',
    'motherfucker',
    'nigga',
    'nigger',
    'porn',
    'porno',
    'prick',
    'pussy',
    'retard',
    'shit',
    'shyt',
    'slut',
    'tits',
    'titties',
    'twat',
    'wanker',
    'whore',
    'anjing',
    'babi',
    'bangsat',
    'bapok',
    'burit',
    'celaka',
    'cibai',
    'chibai',
    'cheebai',
    'chebai',
    'haramjadah',
    'hamkachan',
    'jubur',
    'kimak',
    'konek',
    'lancau',
    'lanciau',
    'lancap',
    'makcibai',
    'najis',
    'pelacur',
    'pondan',
    'puki',
    'pukimak',
    'pokimak',
    'pantat',
    'pantek',
    'pntek',
    'sial',
    'sundal',
    'tetek',
    'cao',
    'caonima',
    'diu',
    'goubi',
    'hundan',
    'jiba',
    'jianren',
    'jianhuo',
    'nima',
    'pokgai',
    'pokkai',
    'shabi',
    'tamade',
    'wangbadan',
    'kootha',
    'koothi',
    'kasmalam',
    'mundam',
    'otha',
    'ootha',
    'ool',
    'oolu',
    'pundai',
    'sunni',
    'thevdiya',
    'thevdiyapaya',
  };

  static const _blockedScriptPhrases = <String>{
    '操你妈',
    '肏你妈',
    '操你',
    '肏你',
    '干你妈',
    '幹你妈',
    '幹你媽',
    '你妈',
    '你媽',
    '妈的',
    '媽的',
    '他妈',
    '他媽',
    '草泥马',
    '草泥馬',
    '尼玛',
    '尼瑪',
    '鸡巴',
    '雞巴',
    '傻逼',
    '二逼',
    '屄',
    '王八蛋',
    '狗屁',
    '贱人',
    '賤人',
    '贱货',
    '賤貨',
    '混蛋',
    '仆街',
    '撚',
    '屌',
    'ஒத்த',
    'ஓல்',
    'புண்டை',
    'கூதி',
    'தேவடிய',
    'கஸ்மாலம்',
    'முண்டம்',
    'சுன்னி',
    'பொண்டான்',
  };

  static bool hasProfanity(String input) => firstProfanity(input) != null;

  static String? firstProfanity(String input) {
    final normalized = _normalize(input);
    if (normalized.isEmpty) return null;
    final allTokens = normalized
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((token) => token.isNotEmpty)
        .toList();
    final tokens = allTokens.where((token) => token.length >= 2).toSet();
    final joined = allTokens.join();
    for (final word in _blockedWords) {
      final collapsed = _collapse(word);
      if (tokens.contains(word) ||
          (collapsed != word &&
              collapsed.length >= 3 &&
              tokens.contains(collapsed))) {
        return word;
      }
      if (word.length >= 5 && joined.contains(word)) {
        return word;
      }
    }
    for (final phrase in _blockedScriptPhrases) {
      final collapsed = _collapse(phrase);
      if (normalized.contains(phrase) ||
          (collapsed != phrase &&
              collapsed.length >= 3 &&
              normalized.contains(collapsed))) {
        return phrase;
      }
    }
    return null;
  }

  static String _normalize(String input) {
    var text = input.toLowerCase();
    for (final entry in _leetMap.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return _collapse(text);
  }

  static String _collapse(String input) => input.replaceAllMapped(
    RegExp(r'(.)\1+', unicode: true),
    (match) => match.group(1) ?? '',
  );

  static const _leetMap = <String, String>{
    '@': 'a',
    '4': 'a',
    '8': 'b',
    '3': 'e',
    '1': 'i',
    '!': 'i',
    '0': 'o',
    '5': 's',
    '\$': 's',
    '7': 't',
  };
}
