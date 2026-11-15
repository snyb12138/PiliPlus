import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models/user/danmaku_spam/template_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vectors = jsonDecode(
    File('test_vectors/danmaku_spam/v1.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  group('template classification vectors', () {
    for (final rawCase in vectors['templates'] as List<dynamic>) {
      final testCase = rawCase as Map<String, dynamic>;
      test(testCase['caseId'] as String, () {
        final result = TemplateSpamTracker.classify(
          testCase['input'] as String,
        );
        expect(result?.reason.name, testCase['expectedReason']);
        expect(result?.templateKey, testCase['expectedTemplateKey']);
      });
    }
  });

  test('classifies only whole-message count and relative-time templates', () {
    final count = TemplateSpamTracker.classify(' ５０００ ＋ ');
    final minutes = TemplateSpamTracker.classify('5 分钟前');
    final hours = TemplateSpamTracker.classify('5小时前');

    expect(count?.reason, TemplateSpamReason.peopleCount);
    expect(count?.normalizedText, '5000 +');
    expect(count?.templateKey, '<count>+');
    expect(minutes?.templateKey, '<n>分钟前');
    expect(hours?.templateKey, '<n>小时前');
    expect(minutes?.templateKey, isNot(hours?.templateKey));
    expect(TemplateSpamTracker.classify('在线人数达到5000+'), isNull);
    expect(TemplateSpamTracker.classify('我5分钟前刚看到'), isNull);
  });

  test('global window keeps two and blocks the third template message', () {
    final tracker = TemplateSpamTracker(processSalt: 1);

    expect(
      tracker.inspect(
        cid: 1,
        eventId: '1',
        content: '4分钟前',
        progress: 0,
        sender: 'a',
      ),
      isNull,
    );
    expect(
      tracker.inspect(
        cid: 1,
        eventId: '2',
        content: '5分钟前',
        progress: 1000,
        sender: 'b',
      ),
      isNull,
    );
    final hit = tracker.inspect(
      cid: 1,
      eventId: '3',
      content: '6分钟前',
      progress: 2500,
      sender: 'c',
    );

    expect(hit?.reason, TemplateSpamReason.relativeTime);
    expect(hit?.templateKey, '<n>分钟前');
    expect(hit?.countAtHit, 3);
    expect(hit?.sameSenderCountAtHit, 1);
    expect(hit?.windowStartProgress, 0);
    expect(hit?.windowEndProgress, 2500);
  });

  test('five-second boundary is left-closed and right-open', () {
    final tracker = TemplateSpamTracker(processSalt: 1);

    tracker
      ..inspect(
        cid: 1,
        eventId: '1',
        content: '5000+',
        progress: 0,
        sender: 'a',
      )
      ..inspect(
        cid: 1,
        eventId: '2',
        content: '6000+',
        progress: 1000,
        sender: 'b',
      );
    final boundary = tracker.inspect(
      cid: 1,
      eventId: '3',
      content: '7000+',
      progress: 5000,
      sender: 'c',
    );

    expect(boundary, isNull);
  });

  test('same sender window groups equal and different numeric versions', () {
    final tracker = TemplateSpamTracker(processSalt: 1);

    tracker
      ..inspect(
        cid: 1,
        eventId: '1',
        content: '5分钟前',
        progress: 0,
        sender: 'same',
      )
      ..inspect(
        cid: 1,
        eventId: '2',
        content: '5分钟前',
        progress: 6000,
        sender: 'same',
      );
    final hit = tracker.inspect(
      cid: 1,
      eventId: '3',
      content: '6分钟前',
      progress: 9999,
      sender: 'same',
    );

    expect(hit?.reason, TemplateSpamReason.relativeTime);
    expect(hit?.countAtHit, 2);
    expect(hit?.sameSenderCountAtHit, 3);
    expect(hit?.senderHash, isNot('same'));
  });

  test('ten-second sender boundary starts a new window', () {
    final tracker = TemplateSpamTracker(processSalt: 1);

    tracker
      ..inspect(
        cid: 1,
        eventId: '1',
        content: '5分钟前',
        progress: 0,
        sender: 'same',
      )
      ..inspect(
        cid: 1,
        eventId: '2',
        content: '5分钟前',
        progress: 6000,
        sender: 'same',
      );
    final boundary = tracker.inspect(
      cid: 1,
      eventId: '3',
      content: '6分钟前',
      progress: 10000,
      sender: 'same',
    );

    expect(boundary, isNull);
  });

  test('reloaded event returns its decision without incrementing counts', () {
    final tracker = TemplateSpamTracker(processSalt: 1);

    tracker
      ..inspect(
        cid: 1,
        eventId: '1',
        content: '5000+',
        progress: 0,
        sender: 'a',
      )
      ..inspect(
        cid: 1,
        eventId: '2',
        content: '6000+',
        progress: 1000,
        sender: 'b',
      );
    final first = tracker.inspect(
      cid: 1,
      eventId: '3',
      content: '7000+',
      progress: 2000,
      sender: 'c',
    );
    final replay = tracker.inspect(
      cid: 1,
      eventId: '3',
      content: '7000+',
      progress: 2000,
      sender: 'c',
    );
    final fourth = tracker.inspect(
      cid: 1,
      eventId: '4',
      content: '8000+',
      progress: 3000,
      sender: 'd',
    );

    expect(replay?.countAtHit, first?.countAtHit);
    expect(fourth?.countAtHit, 4);
  });

  test('cid state is isolated and least-recent non-current state is evicted', () {
    final tracker = TemplateSpamTracker(processSalt: 1, maxResidentCids: 3)
      ..activateCid(1)
      ..activateCid(2)
      ..activateCid(3)
      ..activateCid(1)
      ..activateCid(4);

    expect(tracker.residentCids, orderedEquals(<int>[3, 1, 4]));

    tracker
      ..inspect(
        cid: 1,
        eventId: '1',
        content: '5000+',
        progress: 0,
        sender: 'a',
      )
      ..inspect(
        cid: 1,
        eventId: '2',
        content: '6000+',
        progress: 1000,
        sender: 'b',
      );
    expect(
      tracker.inspect(
        cid: 4,
        eventId: '3',
        content: '7000+',
        progress: 2000,
        sender: 'c',
      ),
      isNull,
    );
  });

  test('an inactive late event cannot evict the active cid', () {
    final tracker = TemplateSpamTracker(processSalt: 1, maxResidentCids: 3)
      ..activateCid(1)
      ..activateCid(2)
      ..activateCid(3)
      ..activateCid(1);

    tracker.inspect(
      cid: 4,
      eventId: 'late',
      content: '5000+',
      progress: 0,
      sender: 'late',
    );

    expect(tracker.residentCids, contains(1));
    expect(tracker.residentCids, orderedEquals(<int>[3, 1, 4]));
  });
}
