import 'dart:convert';

import 'package:PiliPlus/models/user/jm_reading_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = JmCommentSource(
    aid: '123456789',
    rootId: '9007199254740993',
    replyId: '9007199254740994',
    videoTitle: '原视频标题',
    excerpt: '编号是 123456',
  );
  const another = JmCommentSource(
    aid: '987654321',
    rootId: '7',
    replyId: '7',
    excerpt: '也推荐 123456',
  );

  test(
    'extracts distinct whole runs in order and handles fullwidth digits',
    () {
      expect(
        JmReadingList.extractIds('推荐１２３４５６、234567，JM123456、12，123456789'),
        ['123456', '234567'],
      );
      expect(JmReadingList.extractIds('00001 12345678 9999'), [
        '00001',
        '12345678',
      ]);
      expect(JmReadingList.extractIds('123 456'), isEmpty);
    },
  );

  test('deduplicates IDs and preserves each distinct comment source', () {
    var entries = JmReadingList.add([], ['123456', '123456'], source);
    entries = JmReadingList.add(entries, ['123456'], source);
    entries = JmReadingList.add(entries, ['123456', '234567'], another);
    expect(entries.map((entry) => entry.id), ['123456', '234567']);
    expect(entries.first.sources, [source, another]);
  });

  test('round trips local source metadata without truncating comment IDs', () {
    final stored = jsonDecode(
      jsonEncode(const JmReadingEntry('123456', [source])),
    );
    final restored = JmReadingEntry.fromJson(stored as Map<String, dynamic>);
    expect(restored.sources.single.link.queryParameters, {
      'comment_on': '1',
      'comment_root_id': source.rootId,
      'comment_secondary_id': source.replyId,
    });
    expect(another.link.queryParameters['comment_secondary_id'], isNull);
    expect(restored.sources.single.videoTitle, source.videoTitle);
    expect(restored.sources.single.excerpt, source.excerpt);
  });

  test('exports exactly the JM Lite share schema without source details', () {
    final entries = [
      const JmReadingEntry('123456', [source]),
    ];
    expect(
      jsonDecode(
        JmReadingList.encodeShare(entries, DateTime.utc(2026, 11, 27)),
      ),
      {
        'type': 'jm-lite-favorites',
        'version': 1,
        'exportedAt': '2026-11-27T00:00:00.000Z',
        'comicIds': ['123456'],
      },
    );
    expect(entries.single.sources.single, source);
  });
}
