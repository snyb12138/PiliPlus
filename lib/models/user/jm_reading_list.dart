import 'dart:convert';

abstract final class JmReadingList {
  static final _digits = RegExp(r'[0-9]+');

  static String _normalizeDigits(String text) => String.fromCharCodes(
    text.runes.map(
      (rune) => rune >= 0xff10 && rune <= 0xff19 ? rune - 0xfee0 : rune,
    ),
  );

  /// Search treats every digit in one comment as a single ordered candidate.
  static String? assembleSearchCandidate(String comment) {
    final digits = _digits
        .allMatches(_normalizeDigits(comment))
        .map((match) => match.group(0)!)
        .join();
    return digits.length > 4 ? digits : null;
  }

  static List<String> extractSelectionIds(String selection) {
    final ids = extractIds(selection);
    if (ids.isNotEmpty) return ids;
    final assembled = assembleSearchCandidate(selection);
    return assembled != null && assembled.length <= 8 ? [assembled] : [];
  }

  /// Split before filtering by length so two IDs never become one.
  static List<String> extractIds(String selection) {
    final normalized = _normalizeDigits(selection);
    return {
      for (final match in _digits.allMatches(normalized))
        if (match.end - match.start >= 5 && match.end - match.start <= 8)
          match.group(0)!,
    }.toList();
  }

  static String encodeShare(Iterable<JmReadingEntry> entries, DateTime now) =>
      const JsonEncoder.withIndent('  ').convert({
        'type': 'jm-lite-favorites',
        'version': 1,
        'exportedAt': now.toUtc().toIso8601String(),
        'comicIds': [for (final entry in entries) entry.id],
      });

  static List<JmReadingEntry> add(
    List<JmReadingEntry> entries,
    Iterable<String> ids,
    JmCommentSource source,
  ) {
    final byId = {for (final entry in entries) entry.id: entry};
    for (final id in ids) {
      final current = byId[id];
      if (current == null) {
        byId[id] = JmReadingEntry(id, [source]);
      } else if (!current.sources.any((item) => item.key == source.key)) {
        byId[id] = JmReadingEntry(id, [...current.sources, source]);
      }
    }
    return byId.values.toList();
  }
}

class JmReadingEntry {
  const JmReadingEntry(this.id, this.sources);
  final String id;
  final List<JmCommentSource> sources;

  factory JmReadingEntry.fromJson(Map<String, dynamic> json) => JmReadingEntry(
    json['id'] as String,
    (json['sources'] as List)
        .map((item) => JmCommentSource.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sources': [for (final source in sources) source.toJson()],
  };
}

class JmCommentSource {
  const JmCommentSource({
    required this.aid,
    required this.rootId,
    required this.replyId,
    required this.excerpt,
    this.videoTitle,
  });
  final String aid;
  final String rootId;
  final String replyId;
  final String excerpt;
  final String? videoTitle;

  (String, String) get key => (aid, replyId);

  Uri get link => Uri.https('www.bilibili.com', '/video/av$aid', {
    'comment_on': '1',
    'comment_root_id': rootId,
    if (replyId != rootId) 'comment_secondary_id': replyId,
  });

  factory JmCommentSource.fromJson(Map<String, dynamic> json) =>
      JmCommentSource(
        aid: json['aid'] as String,
        rootId: json['rootId'] as String,
        replyId: json['replyId'] as String,
        excerpt: json['excerpt'] as String,
        videoTitle: json['videoTitle'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'aid': aid,
    'rootId': rootId,
    'replyId': replyId,
    'excerpt': excerpt,
    if (videoTitle != null) 'videoTitle': videoTitle,
  };
}
