import 'package:PiliPlus/models/user/jm_reading_list.dart';
import 'package:PiliPlus/models/user/reply_number_scan.dart';

/// Runs without Flutter as well as through the test harness.
Future<void> main() async {
  void check(bool condition, String label) {
    if (!condition) throw StateError(label);
  }

  check(
    JmReadingList.assembleSearchCandidate('119 把、29 次、84 分') == '1192984',
    'split digits',
  );
  check(
    JmReadingList.assembleSearchCandidate('００１ 与 ２３') == '00123',
    '5 digits, full-width and leading zeros',
  );
  check(
    JmReadingList.assembleSearchCandidate('12 和 34') == null,
    'reject four digits',
  );
  check(
    JmReadingList.assembleSearchCandidate('12345 和 67890') == '1234567890',
    'keep all digits in order',
  );
  check(
    JmReadingList.extractSelectionIds('119 把、29 次、84 分').single == '1192984',
    'selection fallback',
  );
  check(
    JmReadingList.extractSelectionIds('123456、234567').length == 2,
    'preserve explicit selection ids',
  );
  check(
    JmReadingList.extractIds('123456789').isEmpty,
    'do not import a truncated candidate',
  );

  const preview = ReplyNumberComment(
    id: '11',
    rootId: '1',
    message: '预览 123456',
  );
  const root = ReplyNumberComment(
    id: '1',
    rootId: '1',
    message: '主楼 1234',
    hasReplies: true,
    replies: [preview],
  );
  const deeperReply = ReplyNumberComment(
    id: '12',
    rootId: '1',
    message: '楼 12 34 56',
  );
  const folded = ReplyNumberComment(
    id: '13',
    rootId: '1',
    message: '折叠 1 23 45',
  );
  final scan = ReplyNumberScan(startRootId: '1');
  final calls = <ReplyNumberCursor>[];
  Future<ReplyNumberPage> load(ReplyNumberCursor request) async {
    calls.add(request);
    return switch (request) {
      (rootId: null, offset: null, folded: false) => const ReplyNumberPage([
        root,
      ], nextOffset: 'more-main'),
      (rootId: '1', offset: null, folded: false) => const ReplyNumberPage(
        [root],
        nextOffset: 'more-replies',
        foldOffset: 'fold',
      ),
      (rootId: null, offset: 'more-main', folded: false) =>
        const ReplyNumberPage([root], nextOffset: 'more-main'),
      (rootId: '1', offset: 'more-replies', folded: false) =>
        const ReplyNumberPage([deeperReply]),
      (rootId: '1', offset: 'fold', folded: true) => const ReplyNumberPage([
        folded,
      ]),
      _ => throw StateError('unexpected request $request'),
    };
  }

  for (var i = 0; scan.hasMore && i < 10; i++) {
    await scan.step(load);
  }
  check(
    !scan.hasMore && calls.length == 5,
    'finishes and ignores repeated cursor',
  );
  check(scan.scanned == 4, 'comments deduped');
  check(
    scan.candidates.map((item) => item.comment.id).join(',') == '11,12,13',
    'preview, next page and folded replies',
  );
  check(
    scan.candidates.last.comment.rootId == '1' &&
        scan.candidates.last.number == '12345',
    'root retained and 5-digit fold candidate',
  );

  final retryScan = ReplyNumberScan();
  try {
    await retryScan.step((_) async => throw StateError('load failed'));
  } on StateError {
    check(
      retryScan.hasMore && retryScan.scanned == 0,
      'preserve failing page for retry',
    );
  }
  retryScan.skipPage();
  check(
    !retryScan.hasMore && retryScan.skippedPages == 1,
    'skipped pages remain visible',
  );
}
