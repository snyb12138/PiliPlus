import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models/user/reply_ai_filter.dart';
import 'package:PiliPlus/models/user/reply_density_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test_vectors/reply_density/v1.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  test('canonical vector schema matches detector enums', () {
    expect(fixture['schemaVersion'], 1);
    expect(
      fixture['candidateTypes'],
      ReplyDensityCandidateType.values.map((value) => value.name).toList(),
    );
  });

  test('canonical vectors cover the phase-one quality gate', () {
    final coverage = cases
        .expand((item) => (item['coverage'] as List).cast<String>())
        .toSet();

    expect(
      coverage,
      containsAll(const {
        'singlePureMention',
        'multiplePureMentions',
        'shortText',
        'pureEmote',
        'pureImage',
        'fishNicknameWeakEvidence',
        'templateStyle',
        'candidateExclusivity',
        'dualMentionMetrics',
      }),
    );
  });

  group('canonical reply density vectors', () {
    for (final vector in cases) {
      final caseId = vector['caseId'] as String;

      test(caseId, () {
        final input = vector['input'] as Map<String, dynamic>;
        final configJson = input['config'] as Map<String, dynamic>;
        final expected = vector['expected'] as Map<String, dynamic>;

        final result = ReplyDensityDetector.assess(
          message: input['message'] as String,
          atNameToMid: (input['atNameToMid'] as Map).map(
            (key, value) => MapEntry(key as String, value as int),
          ),
          structuredEmotes: (input['structuredEmotes'] as List).cast<String>(),
          hasPictures: input['hasPictures'] as bool,
          nickname: input['nickname'] as String,
          repeatedMentionCount: input['repeatedMentionCount'] as int,
          config: ReplyDensityConfig(
            foldPureMentions: configJson['foldPureMentions'] as bool,
            multipleMentionThreshold:
                configJson['multipleMentionThreshold'] as int,
            shortTextMaxCharacters:
                configJson['shortTextMaxCharacters'] as int,
          ),
        );

        expect(result.candidateType.name, expected['candidateType']);
        expect(
          result.mentionOccurrenceCount,
          expected['mentionOccurrenceCount'],
        );
        expect(
          result.distinctMentionMidCount,
          expected['distinctMentionMidCount'],
        );
        expect(result.effectiveTextLength, expected['effectiveTextLength']);
        expect(result.shouldFold, expected['shouldFold']);
        expect(result.pendingReview, expected['pendingReview']);
        expect(
          result.shouldPermanentlyBlock,
          expected['shouldPermanentlyBlock'],
        );
        expect(
          result.aiAssessment.signals
              .map((signal) => signal.name)
              .toList(),
          expected['aiSignals'],
        );
        expect(
          result.aiAssessment.matches(ReplyAiFilterLevel.balanced),
          expected['matchesBalancedAiFilter'],
        );
        expect(result.reasonLabels, expected['reasonLabels']);
      });
    }
  });

  test('density text can exclude a nested prefix without hiding AI evidence', () {
    final result = ReplyDensityDetector.assess(
      message: '@目标账号',
      aiMessage: '回复 @上层账号 : 作为一个 AI 语言模型，我无法判断。',
      atNameToMid: const {'目标账号': 1001, '上层账号': 1002},
      config: const ReplyDensityConfig(foldPureMentions: true),
    );

    expect(
      result.candidateType,
      ReplyDensityCandidateType.singlePureMention,
    );
    expect(result.mentionOccurrenceCount, 1);
    expect(result.distinctMentionMidCount, 1);
    expect(result.shouldFold, isTrue);
    expect(
      result.aiAssessment.signals,
      contains(ReplyAiSignal.modelDisclosure),
    );
  });


  group('per-video purify session', () {
    test('ignored replies stay isolated by video', () {
      final first = ReplyPurifyVideoSession(videoId: 100);
      final second = ReplyPurifyVideoSession(videoId: 200);

      expect(first.ignore(9001), isTrue);
      expect(first.ignore(9001), isFalse);
      expect(first.isIgnored(9001), isTrue);
      expect(second.isIgnored(9001), isFalse);
      expect(first.ignoredReplyIds, const {9001});
    });

    test('ignored replies can be restored without touching permanent rules', () {
      final session = ReplyPurifyVideoSession(videoId: 100);

      expect(session.ignore(0), isFalse);
      expect(session.ignore(9001), isTrue);
      expect(session.restore(9001), isTrue);
      expect(session.restore(9001), isFalse);
      expect(session.ignoredCount, 0);

      session
        ..ignore(9002)
        ..ignore(9003);
      expect(session.clearIgnored(), isTrue);
      expect(session.clearIgnored(), isFalse);
      expect(session.ignoredReplyIds, isEmpty);
    });


    test('only the latest recoverable action is retained per video', () {
      final session = ReplyPurifyVideoSession(videoId: 100);
      const first = ReplyPurifyUndoAction.muteUser(
        mid: 42,
        name: '测试账号',
      );
      const second = ReplyPurifyUndoAction.keywordPattern(
        previousPattern: '旧规则',
      );

      session.rememberUndo(first);
      expect(session.undoAction, same(first));
      expect(first.requiresReplyReload, isTrue);
      expect(first.label, '屏蔽 @测试账号');

      session.rememberUndo(second);
      expect(session.undoAction, same(second));
      expect(session.clearUndo(first), isFalse);
      expect(session.clearUndo(second), isTrue);
      expect(session.undoAction, isNull);
      expect(session.clearUndo(), isFalse);
    });

    test('mark actions remain local and do not require a reply reload', () {
      const added = ReplyPurifyUndoAction.markUser(
        mid: 42,
        name: '测试账号',
      );
      const removed = ReplyPurifyUndoAction.unmarkUser(
        mid: 42,
        name: '测试账号',
      );

      expect(added.requiresReplyReload, isFalse);
      expect(removed.requiresReplyReload, isFalse);
      expect(added.label, '标记 @测试账号');
      expect(removed.label, '取消标记 @测试账号');
    });
  });

}
