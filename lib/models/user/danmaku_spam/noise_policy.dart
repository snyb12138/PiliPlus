/// Opt-in aggressive filtering. These are lexical signals, not a claim that
/// text is semantically meaningless. Manual allowlists always take priority.
abstract final class DanmakuNoisePolicy {
  static final RegExp _latin = RegExp(r'[a-zＡ-Ｚａ-ｚ]', caseSensitive: false);
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

  static bool containsLatin(String content) => _latin.hasMatch(content);

  static bool isAllowed(String content, Iterable<String> whitelist) =>
      whitelist.any((entry) => key(entry) == key(content));

  /// [isolated] is null when adjacent segments do not provide full +/-2s
  /// coverage. Unknown coverage never counts as evidence of isolation.
  static List<String> reasons(String content, {required bool? isolated}) {
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
