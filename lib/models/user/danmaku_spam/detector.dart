import 'dart:collection';
import 'dart:math';

enum DanmakuSpamReason {
  decorativeSymbols('装饰符号刷屏'),
  questionBangSymbols('问叹符号刷屏'),
  mixedSymbols('纯符号刷屏'),
  expressiveCharacter('语气字符重复'),
  repeatedCharacter('单字符重复'),
  repeatedPhrase('短句周期重复'),
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
  DanmakuSpamDetector({
    int? processSalt,
    this.maxTrackedKeys = 4096,
  }) : _processSalt = processSalt ?? _defaultProcessSalt;

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
    final repeatCount = hasRepeatedUnit
        ? keyRunes.length ~/ periodLength
        : 1;
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
  }) {
    final normalized = normalize(content);
    if (normalized.normalizedKey.isEmpty) return null;
    if (_allowedKeys.contains(normalized.repeatBaseKey)) return null;

    final senderHash = _hashSender(sender);
    final internalReason = _internalReason(normalized);
    if (internalReason != null) {
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
    final events = _touchEvents(key);
    events.removeWhere(
      (event) => progress - event.progress > senderWindowMilliseconds,
    );
    events.add(_SpamEvent(progress: progress, sender: sender));

    final globalEvents = events
        .where(
          (event) =>
              progress - event.progress >= 0 &&
              progress - event.progress <= globalWindowMilliseconds,
        )
        .toList(growable: false);
    final sameSenderCount = events
        .where(
          (event) =>
              event.sender == sender &&
              progress - event.progress >= 0 &&
              progress - event.progress <= senderWindowMilliseconds,
        )
        .length;
    final sameSenderHit = sameSenderCount >= senderWindowThreshold;
    final globalHit = globalEvents.length >= globalWindowThreshold;
    if (!sameSenderHit && !globalHit) return null;

    final reason = sameSenderHit
        ? DanmakuSpamReason.sameSenderWindow
        : DanmakuSpamReason.globalWindow;
    final relevantEvents = sameSenderHit
        ? events.where((event) => event.sender == sender)
        : globalEvents;
    final windowStart = relevantEvents.fold<int>(
      progress,
      (value, event) => min(value, event.progress),
    );

    return DanmakuSpamMatch(
      reason: reason,
      normalizedKey: normalized.normalizedKey,
      repeatBaseKey: normalized.repeatBaseKey,
      countAtHit: globalEvents.length,
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

  static DanmakuSpamReason? _internalReason(
    DanmakuSpamNormalized normalized,
  ) {
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

    if (normalized.repeatCount < 2) return null;
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
