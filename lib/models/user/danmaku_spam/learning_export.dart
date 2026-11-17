import 'package:PiliPlus/models/user/danmaku_spam/learning_sample.dart';

abstract final class DanmakuLearningExport {
  static const schema = 'piliplus-danmaku-learning/v2';

  static Map<String, Object> build({
    required Iterable<DanmakuLearningSample> samples,
    required Iterable<String> whitelist,
  }) {
    final normalizedWhitelist = <String>[];
    final seen = <String>{};
    for (final entry in whitelist) {
      final value = entry.trim();
      if (value.isNotEmpty && seen.add(value)) {
        normalizedWhitelist.add(value);
      }
    }
    return {
      'schema': schema,
      'samples': samples.map((item) => item.toStorage()).toList(),
      'whitelist': normalizedWhitelist,
    };
  }
}
