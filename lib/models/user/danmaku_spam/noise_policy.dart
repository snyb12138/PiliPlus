/// Opt-in aggressive filtering. These are lexical signals, not a claim that
/// text is semantically meaningless. Manual allowlists always take priority.
abstract final class DanmakuNoisePolicy {
  static final RegExp _latin = RegExp(r'[a-zＡ-Ｚａ-ｚ]', caseSensitive: false);
  static final RegExp _asciiDigits = RegExp(r'^[0-9]+$');
  static final RegExp _letter = RegExp(
    r'\p{L}',
    unicode: true,
  );
  static final RegExp _number = RegExp(
    r'\p{N}',
    unicode: true,
  );
  static final RegExp _zeroWidth = RegExp(
    '[\u00ad\u200b\u200c\u200d\u2060\ufeff]',
  );
  static final RegExp _whitespace = RegExp(r'\s+', unicode: true);
  static final RegExp _punctuation = RegExp(
    r'''[。！？!?，,；;：:/\\*.》〈〉《「」【】“”‘’"']''',
  );
  static const Set<String> commonCombinations = {
    'nb',
    'yyds',
    'gg',
    'ggwp',
    'lol',
    'lmao',
    'wtf',
    'doge',
    'nice',
    'ok',
    'okay',
    'emmm',
    'awsl',
    'hahaha',
  };

  static String key(String content) {
    final buffer = StringBuffer();
    for (final rune in content.runes) {
      buffer.writeCharCode(
        rune == 0x3000
            ? 0x20
            : rune >= 0xff01 && rune <= 0xff5e
            ? rune - 0xfee0
            : rune,
      );
    }
    return buffer.toString().trim().toLowerCase();
  }

  static String _compactKey(String content) => key(
    content,
  ).replaceAll(_zeroWidth, '').replaceAll(_whitespace, '');

  static bool isShortPureNumber(String content) {
    final normalized = _compactKey(content);
    return normalized.length <= 2 && _asciiDigits.hasMatch(normalized);
  }

  static bool containsLatin(String content) => _latin.hasMatch(content);

  static bool isAllowed(String content, Iterable<String> whitelist) =>
      whitelist.any((entry) => key(entry) == key(content));

  /// [isolated] is null when adjacent segments do not provide full +/-2s
  /// coverage. Unknown coverage never counts as evidence of isolation.
  static List<String> reasons(String content, {required bool? isolated}) {
    final normalized = _compactKey(content);
    if (normalized.isEmpty) return const [];

    // Exact 666 remains the only built-in numeric exemption. Manual exact
    // allowlists still run before this policy and may exempt any other value.
    if (_asciiDigits.hasMatch(normalized)) {
      return normalized == '666' ? const [] : const ['纯数字弹幕'];
    }

    final hasAsciiDigit = normalized.runes.any(
      (rune) => rune >= 0x30 && rune <= 0x39,
    );
    final hasSymbol = normalized.runes.any(
      (rune) =>
          !_letter.hasMatch(String.fromCharCode(rune)) &&
          !_number.hasMatch(String.fromCharCode(rune)),
    );
    final hasLetter = normalized.runes.any(
      (rune) => _letter.hasMatch(String.fromCharCode(rune)),
    );
    if (hasAsciiDigit && hasSymbol && !hasLetter) {
      return const ['数字与符号组合'];
    }

    if (!hasLetter && hasSymbol) {
      final questionBangOnly = normalized.runes.every(
        (rune) => rune == 0x3f || rune == 0x21,
      );
      if (!questionBangOnly) return const ['冷僻符号组合'];
    }

    if (!containsLatin(content)) return const [];
    return [
      if (isolated == true) '前后 2 秒无其他含英文弹幕',
      if (_punctuation.allMatches(content).length >= 2) '混杂标点/特殊字符',
      if (!commonCombinations.contains(key(content))) '不在常用网络组合表',
    ];
  }

  /// Works on a time-sorted raw batch before merging or removing any item.
  /// At segment boundaries, full coverage is required before returning true.
  static List<bool?> isolatedFlags(
    List<({String content, int progress})> items, {
    required int coverageStart,
    required int coverageEnd,
  }) {
    final latinIndices = <int>[
      for (var i = 0; i < items.length; i++)
        if (containsLatin(items[i].content)) i,
    ];
    final result = List<bool?>.filled(items.length, null);
    for (var i = 0; i < latinIndices.length; i++) {
      final index = latinIndices[i];
      final time = items[index].progress;
      final hasNeighbor =
          (i > 0 && time - items[latinIndices[i - 1]].progress <= 2000) ||
          (i + 1 < latinIndices.length &&
              items[latinIndices[i + 1]].progress - time <= 2000);
      result[index] = hasNeighbor
          ? false
          : time - 2000 >= coverageStart && time + 2000 < coverageEnd
          ? true
          : null;
    }
    return result;
  }
}
