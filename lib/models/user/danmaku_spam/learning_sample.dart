import 'package:PiliPlus/models/user/danmaku_spam/detector.dart';

/// User-confirmed samples only. No sender, cid, URL or account information.
class DanmakuLearningSample {
  const DanmakuLearningSample({
    required this.content,
    required this.keyword,
    required this.mode,
    this.progress,
    this.count = 1,
  });

  final String content;
  final String keyword;
  final String mode;
  final int? progress;
  final int count;

  static const int maxSamples = 1000;

  static List<DanmakuLearningSample> fromStorage(
    Object? raw, {
    bool migrateShortNumericContains = true,
  }) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw.take(maxSamples))
        if (entry is Map &&
            entry['content'] is String &&
            entry['keyword'] is String &&
            (entry['mode'] == 'contains' || entry['mode'] == 'exact'))
          DanmakuLearningSample(
            content: entry['content'] as String,
            keyword: entry['keyword'] as String,
            mode:
                migrateShortNumericContains &&
                    entry['mode'] == 'contains' &&
                    _isShortPureNumber(entry['keyword'] as String)
                ? 'exact'
                : entry['mode'] as String,
            progress: entry['progress'] is int
                ? entry['progress'] as int
                : null,
            count: entry['count'] is int && (entry['count'] as int) > 0
                ? entry['count'] as int
                : 1,
          ),
    ];
  }

  static bool _isShortPureNumber(String content) {
    final normalized = DanmakuSpamDetector.normalize(content).normalizedKey;
    return normalized.length <= 2 && RegExp(r'^[0-9]+$').hasMatch(normalized);
  }

  static List<DanmakuLearningSample> collect(
    List<DanmakuLearningSample> previous,
    DanmakuLearningSample sample,
  ) {
    final items = List<DanmakuLearningSample>.of(previous);
    final index = items.indexWhere(
      (item) =>
          item.content == sample.content &&
          item.keyword == sample.keyword &&
          item.mode == sample.mode,
    );
    final count = index < 0 ? 1 : items.removeAt(index).count + 1;
    items.insert(
      0,
      DanmakuLearningSample(
        content: sample.content,
        keyword: sample.keyword,
        mode: sample.mode,
        progress: sample.progress,
        count: count,
      ),
    );
    return items.take(maxSamples).toList(growable: false);
  }

  Map<String, Object> toStorage() => {
    'content': content,
    'normalizedText': DanmakuSpamDetector.normalize(content).normalizedKey,
    'keyword': keyword,
    'mode': mode,
    'progress': ?progress,
    'count': count,
  };
}
