import 'dart:collection';
import 'dart:math';

enum TemplateSpamReason {
  peopleCount('人数模板刷屏'),
  relativeTime('时间模板刷屏'),
  symbolFragment('短符号组合刷屏');

  const TemplateSpamReason(this.label);

  final String label;
}

class TemplateSpamCandidate {
  const TemplateSpamCandidate({
    required this.reason,
    required this.normalizedText,
    required this.templateKey,
  });

  final TemplateSpamReason reason;
  final String normalizedText;
  final String templateKey;
}

class TemplateSpamMatch {
  const TemplateSpamMatch({
    required this.reason,
    required this.normalizedText,
    required this.templateKey,
    required this.countAtHit,
    required this.sameSenderCountAtHit,
    required this.windowStartProgress,
    required this.windowEndProgress,
    required this.senderHash,
  });

  final TemplateSpamReason reason;
  final String normalizedText;
  final String templateKey;

  /// Both counters include the current danmaku.
  final int countAtHit;
  final int sameSenderCountAtHit;
  final int windowStartProgress;
  final int windowEndProgress;

  /// Process-local token. It is never persisted or exported.
  final String senderHash;
}

/// Tracks whole-message count and relative-time templates on the raw stream.
///
/// State is isolated per cid. Seen event keys and decisions are retained for
/// the lifetime of the resident cid state so seeking or reloading a segment
/// cannot count the same danmaku twice or change an earlier decision.
class TemplateSpamTracker {
  TemplateSpamTracker({
    int? processSalt,
    this.maxResidentCids = 3,
    this.maxTrackedTemplates = 4096,
  }) : assert(maxResidentCids > 0),
       assert(maxTrackedTemplates > 0),
       _processSalt = processSalt ?? _defaultProcessSalt;

  static const int globalWindowMilliseconds = 5000;
  static const int senderWindowMilliseconds = 10000;
  static const int globalWindowThreshold = 3;
  static const int senderWindowThreshold = 3;

  static final int _defaultProcessSalt = Random.secure().nextInt(1 << 31);
  static final RegExp _whitespace = RegExp(r'\s+', unicode: true);
  static final RegExp _peopleCount = RegExp(r'^(\d{3,7})\s*\+$');
  static final RegExp _symbolFragment = RegExp(
    r'''^(?:[/\\。.,，!?！？;；【】\[\]《》「」“”‘’"']{1,4}|[.。]0|[←→↑↓][+]?\d{1,2})$''',
  );
  static final RegExp _relativeTime = RegExp(
    r'^(\d{1,3}|[零〇一二两三四五六七八九十百]{1,5}|半)\s*(秒|分钟|小时|天)(前)?(?:[，,、 ]*(热乎|热热|热乎乎|热热能吃|热乎能吃|凉了))?$',
  );
  static final RegExp _englishTime = RegExp(
    r'^\d{1,3}\s+(seconds?|minutes?|hours?|days?)(?:\s+ago)?$',
  );
  static final RegExp _trailingPunctuation = RegExp(r'[!！?？。，,.、；;]+$');

  final int _processSalt;
  final int maxResidentCids;
  final int maxTrackedTemplates;
  final LinkedHashMap<int, _TemplateCidState> _states = LinkedHashMap();
  int? _activeCid;

  Iterable<int> get residentCids => _states.keys;

  static TemplateSpamCandidate? classify(String raw) {
    final normalized = _normalize(raw);
    if (normalized.isEmpty) return null;

    if (_peopleCount.hasMatch(normalized)) {
      return TemplateSpamCandidate(
        reason: TemplateSpamReason.peopleCount,
        normalizedText: normalized,
        templateKey: '<count>+',
      );
    }

    if (_symbolFragment.hasMatch(normalized)) {
      return TemplateSpamCandidate(
        reason: TemplateSpamReason.symbolFragment,
        normalizedText: normalized,
        templateKey: '<symbol-fragment>',
      );
    }

    final timeText = normalized.replaceAll(_trailingPunctuation, '').trim();
    if (_relativeTime.firstMatch(timeText) case final match?) {
      final unit = match.group(1) == '半' && match.group(2) == '小时'
          ? '分钟'
          : match.group(2)!;
      final suffix = match.group(3) == null ? '时长' : '前';
      return TemplateSpamCandidate(
        reason: TemplateSpamReason.relativeTime,
        normalizedText: normalized,
        templateKey: '<n>$unit$suffix',
      );
    }

    if (_englishTime.firstMatch(timeText) case final match?) {
      final unit = switch (match.group(1)!.replaceAll(RegExp(r's$'), '')) {
        'second' => '秒',
        'minute' => '分钟',
        'hour' => '小时',
        _ => '天',
      };
      return TemplateSpamCandidate(
        reason: TemplateSpamReason.relativeTime,
        normalizedText: normalized,
        templateKey: '<n>$unit${timeText.endsWith('ago') ? '前' : '时长'}',
      );
    }

    return null;
  }

  void activateCid(int cid) {
    _activeCid = cid;
    _touchState(cid);
  }

  TemplateSpamMatch? inspect({
    required int cid,
    required String eventId,
    required String content,
    required int progress,
    required String sender,
  }) {
    final candidate = classify(content);
    if (candidate == null) return null;

    final state = _touchState(cid);
    final stableEventId = eventId.isEmpty
        ? '$progress|$sender|${candidate.normalizedText}'
        : eventId;
    final eventKey = '$stableEventId|${candidate.templateKey}';
    if (!state.seenEventKeys.add(eventKey)) {
      return state.blockedDecisions[eventKey];
    }

    final senderHash = _hashSender(sender);
    final history = state.touchEvents(
      candidate.templateKey,
      maxTrackedTemplates,
    );
    final events = history.events;
    final event = _TemplateEvent(eventKey: eventKey, progress: progress);
    final insertAt = _lowerBound(
      events,
      progress + 1,
      (event) => event.progress,
    );
    events.insert(insertAt, event);
    final senderTimes = history.bySender.putIfAbsent(senderHash, () => <int>[]);
    final senderEnd = _lowerBound(senderTimes, progress + 1, (time) => time);
    senderTimes.insert(senderEnd, progress);
    final senderStart = _lowerBound(
      senderTimes,
      progress - senderWindowMilliseconds + 1,
      (time) => time,
    );
    final globalStart = _lowerBound(
      events,
      progress - globalWindowMilliseconds + 1,
      (event) => event.progress,
    );
    final globalCount = insertAt + 1 - globalStart;
    final sameSenderCount = senderEnd + 1 - senderStart;
    final globalWindowStart = events[globalStart].progress;
    final sameSenderWindowStart = senderTimes[senderStart];

    final sameSenderHit = sameSenderCount >= senderWindowThreshold;
    final globalHit = globalCount >= globalWindowThreshold;
    if (!sameSenderHit && !globalHit) return null;

    final match = TemplateSpamMatch(
      reason: candidate.reason,
      normalizedText: candidate.normalizedText,
      templateKey: candidate.templateKey,
      countAtHit: globalCount,
      sameSenderCountAtHit: sameSenderCount,
      windowStartProgress: sameSenderHit
          ? sameSenderWindowStart
          : globalWindowStart,
      windowEndProgress: progress,
      senderHash: senderHash,
    );
    state.blockedDecisions[eventKey] = match;
    return match;
  }

  void clearCid(int cid) {
    _states.remove(cid);
    if (_activeCid == cid) _activeCid = null;
  }

  static int _lowerBound<T>(List<T> items, int value, int Function(T) timeOf) {
    var low = 0;
    var high = items.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (timeOf(items[middle]) < value) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  void clear() {
    _states.clear();
    _activeCid = null;
  }

  _TemplateCidState _touchState(int cid) {
    final existing = _states.remove(cid);
    final state = existing ?? _TemplateCidState();
    _states[cid] = state;
    while (_states.length > maxResidentCids) {
      final evictedCid = _states.keys.firstWhere(
        (key) => key != _activeCid,
        orElse: () => cid,
      );
      _states.remove(evictedCid);
    }
    return state;
  }

  String _hashSender(String sender) =>
      Object.hash(_processSalt, sender).toUnsigned(32).toRadixString(16);

  /// Applies the compatibility subset needed by the supported templates:
  /// full-width ASCII/digits and ideographic spaces, then whitespace folding.
  static String _normalize(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      if (rune == 0x3000) {
        buffer.writeCharCode(0x20);
      } else if (rune >= 0xff01 && rune <= 0xff5e) {
        buffer.writeCharCode(rune - 0xfee0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString().replaceAll(_whitespace, ' ').trim().toLowerCase();
  }
}

class _TemplateCidState {
  final LinkedHashMap<String, _TemplateHistory> eventsByTemplate =
      LinkedHashMap();
  final Set<String> seenEventKeys = <String>{};
  final Map<String, TemplateSpamMatch> blockedDecisions =
      <String, TemplateSpamMatch>{};

  _TemplateHistory touchEvents(String key, int maxTrackedTemplates) {
    final existing = eventsByTemplate.remove(key);
    final events = existing ?? _TemplateHistory();
    eventsByTemplate[key] = events;
    if (eventsByTemplate.length > maxTrackedTemplates) {
      final removed = eventsByTemplate.remove(eventsByTemplate.keys.first);
      if (removed != null) {
        for (final event in removed.events) {
          seenEventKeys.remove(event.eventKey);
          blockedDecisions.remove(event.eventKey);
        }
      }
    }
    return events;
  }
}

class _TemplateHistory {
  final List<_TemplateEvent> events = [];
  final Map<String, List<int>> bySender = {};
}

class _TemplateEvent {
  const _TemplateEvent({required this.eventKey, required this.progress});

  final String eventKey;
  final int progress;
}
