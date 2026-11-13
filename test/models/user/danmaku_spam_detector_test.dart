import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models/user/danmaku_spam/detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vectors = jsonDecode(
    File('test_vectors/danmaku_spam/v1.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('test vector schema is pinned', () {
    expect(vectors['schemaVersion'], 1);
  });

  group('normalization vectors', () {
    for (final rawCase in vectors['normalization'] as List<dynamic>) {
      final testCase = rawCase as Map<String, dynamic>;
      test(testCase['caseId'] as String, () {
        final result = DanmakuSpamDetector.normalize(
          testCase['input'] as String,
        );
        expect(result.normalizedKey, testCase['normalizedKey']);
        expect(result.repeatBaseKey, testCase['repeatBaseKey']);
        expect(result.fullLength, testCase['fullLength']);
      });
    }
  });

  group('internal repetition vectors', () {
    for (final rawCase in vectors['internal'] as List<dynamic>) {
      final testCase = rawCase as Map<String, dynamic>;
      test(testCase['caseId'] as String, () {
        final detector = DanmakuSpamDetector(processSalt: 1);
        final match = detector.inspect(
          content: testCase['input'] as String,
          progress: 0,
          sender: 'sender-a',
        );
        expect(match?.reason.name, testCase['expectedReason']);
      });
    }
  });

  test('normalized and repeat keys use the same 64 rune boundary', () {
    final prefix = List<String>.filled(64, '甲').join();
    final exactly64 = DanmakuSpamDetector.normalize(prefix);
    final over64 = DanmakuSpamDetector.normalize('$prefix乙');

    expect(exactly64.wasTruncated, isFalse);
    expect(over64.wasTruncated, isTrue);
    expect(over64.fullLength, 65);
    expect(over64.normalizedKey, exactly64.normalizedKey);
    expect(over64.repeatBaseKey, exactly64.repeatBaseKey);
  });

  test('global window keeps two and blocks the third including itself', () {
    final detector = DanmakuSpamDetector(processSalt: 1);
    expect(
      detector.inspect(content: '收到', progress: 0, sender: 'a'),
      isNull,
    );
    expect(
      detector.inspect(content: '收到', progress: 2000, sender: 'b'),
      isNull,
    );
    final hit = detector.inspect(
      content: '收到',
      progress: 4000,
      sender: 'c',
    );

    expect(hit?.reason, DanmakuSpamReason.globalWindow);
    expect(hit?.countAtHit, 3);
    expect(hit?.sameSenderCountAtHit, 1);
    expect(hit?.windowStartProgress, 0);
    expect(hit?.windowEndProgress, 4000);
  });

  test('same sender ten second window wins when both conditions match', () {
    final detector = DanmakuSpamDetector(processSalt: 1);
    detector
      ..inspect(content: '好耶', progress: 0, sender: 'same')
      ..inspect(content: '好耶', progress: 2000, sender: 'same');
    final hit = detector.inspect(
      content: '好耶',
      progress: 4000,
      sender: 'same',
    );

    expect(hit?.reason, DanmakuSpamReason.sameSenderWindow);
    expect(hit?.countAtHit, 3);
    expect(hit?.sameSenderCountAtHit, 3);
  });

  test('same sender rule can trigger outside the global window', () {
    final detector = DanmakuSpamDetector(processSalt: 1);
    detector
      ..inspect(content: '来了', progress: 0, sender: 'same')
      ..inspect(content: '来了', progress: 6000, sender: 'same');
    final hit = detector.inspect(
      content: '来了',
      progress: 9000,
      sender: 'same',
    );

    expect(hit?.reason, DanmakuSpamReason.sameSenderWindow);
    expect(hit?.countAtHit, 2);
    expect(hit?.sameSenderCountAtHit, 3);
  });

  test('repeat base groups short variants in the same window', () {
    final detector = DanmakuSpamDetector(processSalt: 1);
    expect(detector.inspect(content: '吧', progress: 0, sender: 'a'), isNull);
    expect(
      detector.inspect(content: '吧吧', progress: 1000, sender: 'b'),
      isNull,
    );
    final hit = detector.inspect(
      content: '吧　吧',
      progress: 2000,
      sender: 'c',
    );

    expect(hit?.reason, DanmakuSpamReason.globalWindow);
    expect(hit?.repeatBaseKey, '吧');
    expect(hit?.countAtHit, 3);
  });

  test('current-video allowance bypasses both internal and window rules', () {
    final detector = DanmakuSpamDetector(processSalt: 1)
      ..allowForCurrentVideo('吧');

    expect(
      detector.inspect(content: '吧吧吧吧', progress: 0, sender: 'a'),
      isNull,
    );
    expect(
      detector.inspect(content: '吧', progress: 1000, sender: 'a'),
      isNull,
    );
    expect(
      detector.inspect(content: '吧吧', progress: 2000, sender: 'a'),
      isNull,
    );
    expect(detector.revokeAllowance('吧吧'), isTrue);
    expect(detector.isAllowed('吧'), isFalse);
  });

  test('reset clears window state without leaking across video sessions', () {
    final detector = DanmakuSpamDetector(processSalt: 1);
    detector
      ..inspect(content: '测试', progress: 0, sender: 'a')
      ..inspect(content: '测试', progress: 1000, sender: 'b')
      ..reset(keepAllowances: false);

    expect(
      detector.inspect(content: '测试', progress: 2000, sender: 'c'),
      isNull,
    );
  });
}
