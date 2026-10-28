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
}
