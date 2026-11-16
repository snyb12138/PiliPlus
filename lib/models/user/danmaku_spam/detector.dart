import 'dart:collection';
import 'dart:math';

enum DanmakuSpamReason {
  decorativeSymbols('装饰符号刷屏'),
  questionBangSymbols('问叹符号刷屏'),
  mixedSymbols('纯符号刷屏'),
  expressiveCharacter('语气字符重复'),
  repeatedCharacter('单字符重复'),
  repeatedPhrase('短句周期重复'),
  embeddedCharacterRun('局部字符连打'),
  keyboardMash('疑似键盘乱按'),
  embeddedPhrase('局部短句重复'),
  globalWindow('短句集中刷屏'),
  sameSenderWindow('同用户重复刷屏');

  const DanmakuSpamReason(this.label);

  final String label;
}

class DanmakuSpamNormalized {
  const DanmakuSpamNormalized({
    required this.normalizedKey,
    required this.repeatBaseKey,
    required this.fullLength,
    required this.periodLength,
    required this.repeatCount,
    required this.wasTruncated,
  });

  final String normalizedKey;
  final String repeatBaseKey;
  final int fullLength;
  final int periodLength;
  final int repeatCount;
  final bool wasTruncated;
}

class DanmakuSpamMatch {
  const DanmakuSpamMatch({
    required this.reason,
    required this.normalizedKey,
    required this.repeatBaseKey,
    required this.countAtHit,
    required this.sameSenderCountAtHit,
    required this.windowStartProgress,
    required this.windowEndProgress,
    required this.senderHash,
  });

  final DanmakuSpamReason reason;
  final String normalizedKey;
  final String repeatBaseKey;

  /// Both counters include the current danmaku.
  final int countAtHit;
  final int sameSenderCountAtHit;
  final int windowStartProgress;
  final int windowEndProgress;

  /// Process-local token. It is not suitable for persistence or export.
  final String senderHash;
}

class DanmakuSpamDetector {
  DanmakuSpamDetector({int? processSalt, this.maxTrackedKeys = 4096})
    : _processSalt = processSalt ?? _defaultProcessSalt;

  static const int maxKeyLength = 64;
  static const int maxPeriodLength = 8;
  static const int maxWindowContentLength = 12;
  static const int globalWindowMilliseconds = 5000;
  static const int senderWindowMilliseconds = 10000;
  static const int globalWindowThreshold = 3;
  static const int senderWindowThreshold = 3;

  static final int _defaultProcessSalt = Random.secure().nextInt(1 << 31);
  static final RegExp _zeroWidth = RegExp(
    '[\u00ad\u200b\u200c\u200d\u2060\ufeff]',
  );
  static final RegExp _whitespace = RegExp(r'\s+', unicode: true);
  static final RegExp _symbolOnly = RegExp(
    r'^[^\p{L}\p{N}\s]+$',
    unicode: true,
  );
  static final RegExp _asciiAlphaNumericOnly = RegExp(r'^[a-z0-9]+$');
  static final RegExp _textRune = RegExp(r'^[\p{L}\p{N}]$', unicode: true);
  static const Set<String> _expressiveCharacters = {
    '哈',
    '呵',
    '嘿',
    '啊',
    '哇',
    '呜',
    '草',
    '艹',
    '6',
  };

  final int _processSalt;
  final int maxTrackedKeys;
  final LinkedHashMap<String, List<_SpamEvent>> _events = LinkedHashMap();
  final Set<String> _allowedKeys = <String>{};

  int? _latestProgress;

  static DanmakuSpamNormalized normalize(String raw) {
    var normalized = _foldWidth(raw)
        .replaceAll(_zeroWidth, '')
        .replaceAll(_whitespace, ' ')
        .trim();
    normalized = _removeCjkSpaces(normalized).toLowerCase();

    final fullRunes = normalized.runes.toList(growable: false);
    final wasTruncated = fullRunes.length > maxKeyLength;
    final keyRunes = wasTruncated
        ? fullRunes.take(maxKeyLength).toList(growable: false)
        : fullRunes;
    final normalizedKey = String.fromCharCodes(keyRunes);
    final periodLength = _minimumPeriod(keyRunes);
    final hasRepeatedUnit =
        keyRunes.isNotEmpty &&
        periodLength > 0 &&
        periodLength <= maxPeriodLength &&
        periodLength < keyRunes.length &&
        keyRunes.length % periodLength == 0;
    final repeatCount = hasRepeatedUnit ? keyRunes.length ~/ periodLength : 1;
    final repeatBaseKey = hasRepeatedUnit
        ? String.fromCharCodes(keyRunes.take(periodLength))
        : normalizedKey;

    return DanmakuSpamNormalized(
      normalizedKey: normalizedKey,
      repeatBaseKey: repeatBaseKey,
      fullLength: fullRunes.length,
      periodLength: hasRepeatedUnit ? periodLength : keyRunes.length,
      repeatCount: repeatCount,
      wasTruncated: wasTruncated,
    );
  }

  DanmakuSpamMatch? inspect({
    required String content,
    required int progress,
    required String sender,
    bool compactCharacterRuns = false,
  }) {
    final normalized = normalize(content);
    if (normalized.normalizedKey.isEmpty) return null;
    if (_allowedKeys.contains(normalized.repeatBaseKey)) return null;

    final senderHash = _hashSender(sender);
    final internalReason = _internalReason(normalized);
    final compactedRun =
        compactCharacterRuns &&
        (internalReason == DanmakuSpamReason.expressiveCharacter ||
            internalReason == DanmakuSpamReason.repeatedCharacter ||
            internalReason == DanmakuSpamReason.embeddedCharacterRun) &&
        compactDisplay(content) != content;
    if (internalReason != null && !compactedRun) {
      return DanmakuSpamMatch(
        reason: internalReason,
        normalizedKey: normalized.normalizedKey,
        repeatBaseKey: normalized.repeatBaseKey,
        countAtHit: 1,
        sameSenderCountAtHit: 1,
        windowStartProgress: progress,
        windowEndProgress: progress,
        senderHash: senderHash,
      );
    }

    if (normalized.fullLength < 1 ||
        normalized.fullLength > maxWindowContentLength) {
      return null;
    }

    final latestProgress = _latestProgress;
    if (latestProgress != null &&
        progress < latestProgress - senderWindowMilliseconds) {
      reset();
    }
    _latestProgress = max(_latestProgress ?? progress, progress);

    final key = normalized.repeatBaseKey;
    final events = _touchEvents(key)
      ..removeWhere(
        (event) => progress - event.progress > senderWindowMilliseconds,
      )
      ..add(_SpamEvent(progress: progress, sender: sender));

    var globalCount = 0;
    var sameSenderCount = 0;
    var globalWindowStart = progress;
    var sameSenderWindowStart = progress;
    for (final event in events) {
      final age = progress - event.progress;
      if (age < 0) continue;
      if (age <= globalWindowMilliseconds) {
        globalCount += 1;
        globalWindowStart = min(globalWindowStart, event.progress);
      }
      if (event.sender == sender && age <= senderWindowMilliseconds) {
        sameSenderCount += 1;
        sameSenderWindowStart = min(sameSenderWindowStart, event.progress);
      }
    }
    final sameSenderHit = sameSenderCount >= senderWindowThreshold;
    final globalHit = globalCount >= globalWindowThreshold;
    if (!sameSenderHit && !globalHit) return null;

    final reason = sameSenderHit
        ? DanmakuSpamReason.sameSenderWindow
        : DanmakuSpamReason.globalWindow;
    final windowStart = sameSenderHit
        ? sameSenderWindowStart
        : globalWindowStart;

    return DanmakuSpamMatch(
      reason: reason,
      normalizedKey: normalized.normalizedKey,
      repeatBaseKey: normalized.repeatBaseKey,
      countAtHit: globalCount,
      sameSenderCountAtHit: sameSenderCount,
      windowStartProgress: windowStart,
      windowEndProgress: progress,
      senderHash: senderHash,
    );
  }

  void allowForCurrentVideo(String content) {
    final normalized = normalize(content);
    if (normalized.repeatBaseKey.isEmpty) return;
    _allowedKeys.add(normalized.repeatBaseKey);
    _events.remove(normalized.repeatBaseKey);
  }

  bool revokeAllowance(String content) {
    final normalized = normalize(content);
    return _allowedKeys.remove(normalized.repeatBaseKey);
  }

  bool isAllowed(String content) =>
      _allowedKeys.contains(normalize(content).repeatBaseKey);

  void reset({bool keepAllowances = true}) {
    _events.clear();
    _latestProgress = null;
    if (!keepAllowances) _allowedKeys.clear();
  }

  List<_SpamEvent> _touchEvents(String key) {
    final existing = _events.remove(key);
    final events = existing ?? <_SpamEvent>[];
    _events[key] = events;
    if (_events.length > maxTrackedKeys) {
      _events.remove(_events.keys.first);
    }
    return events;
  }

  String _hashSender(String sender) =>
      Object.hash(_processSalt, sender).toUnsigned(32).toRadixString(16);

  static DanmakuSpamReason? _internalReason(DanmakuSpamNormalized normalized) {
    final key = normalized.normalizedKey;
    final runes = key.runes.toList(growable: false);
    if (runes.isEmpty) return null;

    if (_symbolOnly.hasMatch(key)) {
      final questionBangOnly = runes.every(
        (rune) => rune == 0x3f || rune == 0x21,
      );
      if (questionBangOnly && runes.length >= 4) {
        return DanmakuSpamReason.questionBangSymbols;
      }
      if (runes.length >= 3 && runes.any(_isDecorativeSymbol)) {
        return DanmakuSpamReason.decorativeSymbols;
      }
      if (runes.length >= 5) return DanmakuSpamReason.mixedSymbols;
    }

    if (_hasEmbeddedCharacterRun(runes)) {
      return DanmakuSpamReason.embeddedCharacterRun;
    }
    if (normalized.periodLength != 1 && _looksLikeKeyboardMash(key, runes)) {
      return DanmakuSpamReason.keyboardMash;
    }

    if (normalized.repeatCount < 2) {
      return _hasEmbeddedPhrase(runes)
          ? DanmakuSpamReason.embeddedPhrase
          : null;
    }
    if (normalized.periodLength == 1) {
      final unit = normalized.repeatBaseKey;
      final expressive = _expressiveCharacters.contains(unit);
      final threshold = expressive ? 6 : 4;
      if (normalized.repeatCount >= threshold) {
        return expressive
            ? DanmakuSpamReason.expressiveCharacter
            : DanmakuSpamReason.repeatedCharacter;
      }
      return null;
    }
    if (normalized.periodLength <= maxPeriodLength &&
        normalized.repeatCount >= 3) {
      return DanmakuSpamReason.repeatedPhrase;
    }
    return null;
  }

  static bool _hasEmbeddedPhrase(List<int> runes) {
    // Input is already bounded to 64 code points. Check primitive 2-8-rune
    // units rather than a backtracking regex or runs of the same character.
    for (var start = 0; start + 6 <= runes.length; start++) {
      for (
        var size = 2;
        size <= maxPeriodLength && start + size * 3 <= runes.length;
        size++
      ) {
        var repeated = true;
        for (var offset = 0; offset < size; offset++) {
          if (runes[start + offset] != runes[start + size + offset] ||
              runes[start + offset] != runes[start + size * 2 + offset]) {
            repeated = false;
            break;
          }
        }
        if (!repeated) continue;
        final unit = runes.sublist(start, start + size);
        if (_minimumPeriod(unit) == size &&
            unit.any((rune) => _textRune.hasMatch(String.fromCharCode(rune)))) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _hasEmbeddedCharacterRun(List<int> runes) {
    if (runes.length < 6) return false;
    var runLength = 1;
    for (var i = 1; i < runes.length; i++) {
      if (runes[i] == runes[i - 1]) {
        runLength += 1;
      } else {
        if (runLength >= _embeddedRunThreshold(runes[i - 1])) return true;
        runLength = 1;
      }
    }
    return runLength < runes.length &&
        runLength >= _embeddedRunThreshold(runes.last);
  }

  static int _embeddedRunThreshold(int rune) {
    final asciiLetter =
        (rune >= 0x61 && rune <= 0x7a) || (rune >= 0x41 && rune <= 0x5a);
    if (asciiLetter) return 5;
    if (rune >= 0x30 && rune <= 0x39) return 6;
    if (_expressiveCharacters.contains(String.fromCharCode(rune))) return 6;
    return 4;
  }

  static bool _looksLikeKeyboardMash(String key, List<int> runes) {
    if (runes.length < 16 || !_asciiAlphaNumericOnly.hasMatch(key)) {
      return false;
    }
    var letters = 0;
    var vowels = 0;
    for (final rune in runes) {
      if (rune < 0x61 || rune > 0x7a) continue;
      letters += 1;
      if (rune == 0x61 ||
          rune == 0x65 ||
          rune == 0x69 ||
          rune == 0x6f ||
          rune == 0x75) {
        vowels += 1;
      }
    }
    return letters >= 12 && vowels * 5 <= letters;
  }

  static int _minimumPeriod(List<int> runes) {
    if (runes.isEmpty) return 0;
    final prefix = List<int>.filled(runes.length, 0);
    for (var i = 1; i < runes.length; i++) {
      var j = prefix[i - 1];
      while (j > 0 && runes[i] != runes[j]) {
        j = prefix[j - 1];
      }
      if (runes[i] == runes[j]) j++;
      prefix[i] = j;
    }
    final candidate = runes.length - prefix.last;
    return runes.length % candidate == 0 ? candidate : runes.length;
  }

  /// Rendering only: the original text remains available to filters, preview,
  /// copying and learning. Do not use the shortened text as source evidence.
  static String compactDisplay(String content) {
    final runes = content.runes.toList(growable: false);
    final buffer = StringBuffer();
    var index = 0;
    while (index < runes.length) {
      var end = index + 1;
      while (end < runes.length && runes[end] == runes[index]) {
        end++;
      }
      final isText = _textRune.hasMatch(String.fromCharCode(runes[index]));
      final count = isText ? min(3, end - index) : end - index;
      for (var i = 0; i < count; i++) {
        buffer.writeCharCode(runes[index]);
      }
      index = end;
    }
    return buffer.toString();
  }

  static String _foldWidth(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune == 0x3000) {
        buffer.writeCharCode(0x20);
      } else if (rune >= 0xff01 && rune <= 0xff5e) {
        buffer.writeCharCode(rune - 0xfee0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  static String _removeCjkSpaces(String input) {
    final runes = input.runes.toList(growable: false);
    if (runes.length < 3) return input;
    final buffer = StringBuffer();
    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      final betweenCjk =
          rune == 0x20 &&
          i > 0 &&
          i + 1 < runes.length &&
          _isCjk(runes[i - 1]) &&
          _isCjk(runes[i + 1]);
      if (!betweenCjk) buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  static bool _isCjk(int rune) =>
      (rune >= 0x3400 && rune <= 0x4dbf) ||
      (rune >= 0x4e00 && rune <= 0x9fff) ||
      (rune >= 0xf900 && rune <= 0xfaff);

  static bool _isDecorativeSymbol(int rune) =>
      (rune >= 0x2190 && rune <= 0x21ff) ||
      (rune >= 0x2500 && rune <= 0x259f) ||
      (rune >= 0x25a0 && rune <= 0x25ff);
}

class _SpamEvent {
  const _SpamEvent({required this.progress, required this.sender});

  final int progress;
  final String sender;
}
