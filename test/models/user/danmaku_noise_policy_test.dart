import 'dart:convert';

import 'package:PiliPlus/models/user/danmaku_assistant.dart';
import 'package:PiliPlus/models/user/danmaku_spam/detector.dart';
import 'package:PiliPlus/models/user/danmaku_spam/learning_export.dart';
import 'package:PiliPlus/models/user/danmaku_spam/learning_sample.dart';
import 'package:PiliPlus/models/user/danmaku_spam/noise_policy.dart';
import 'package:PiliPlus/models/user/danmaku_spam/template_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy configs do not enable aggressive filtering', () {
    final config = DanmakuAssistantConfig.fromStorage({'version': 2});
    expect(config.strictNoiseFilter, isFalse);
    expect(config.noiseWhitelist, isEmpty);
    expect(config.learningSamples, isEmpty);
  });

  test('one aggressive signal suffices but only for Latin-containing text', () {
    expect(DanmakuNoisePolicy.reasons('nice', isolated: true), isNotEmpty);
    expect(DanmakuNoisePolicy.reasons('nice', isolated: false), isEmpty);
    expect(
      DanmakuNoisePolicy.reasons('olikgbfdz', isolated: false),
      contains('不在常用网络组合表'),
    );
    expect(
      DanmakuNoisePolicy.reasons('“olikgbfdz”？。4', isolated: null),
      contains('混杂标点/特殊字符'),
    );
    expect(DanmakuNoisePolicy.reasons('这是一句正常中文。', isolated: true), isEmpty);
    expect(DanmakuNoisePolicy.reasons('nice', isolated: null), isEmpty);
  });

  test(
    'isolation uses neighbors on the raw video timeline and known coverage',
    () {
      final result = DanmakuNoisePolicy.isolatedFlags(
        [
          (content: 'near boundary', progress: 1000),
          (content: 'isolated', progress: 5000),
          (content: 'a', progress: 9000),
          (content: 'b', progress: 11000),
          (content: '中文', progress: 13000),
          (content: 'tail', progress: 19900),
        ],
        coverageStart: 0,
        coverageEnd: 20000,
      );
      expect(result, [null, true, false, false, null, null]);
    },
  );

  test(
    'whitelist is exact whole-text matching, never a substring exemption',
    () {
      expect(DanmakuNoisePolicy.isAllowed(' Nice ', ['nice']), isTrue);
      expect(DanmakuNoisePolicy.isAllowed('nice spam', ['nice']), isFalse);
      final config = DanmakuAssistantConfig.defaults().copyWith(
        noiseWhitelist: ['nice'],
        absoluteRules: ['nice'],
      );
      expect(config.match('nice', includeAutomatic: false), isNotNull);
    },
  );

  test('manual learning samples deduplicate without sender/account fields', () {
    const sample = DanmakuLearningSample(
      content: '原文关键词',
      keyword: '关键词',
      mode: 'contains',
      progress: 1234,
    );
    final once = DanmakuLearningSample.collect([], sample);
    final twice = DanmakuLearningSample.collect(once, sample);
    expect(twice.length, 1);
    expect(twice.single.count, 2);
    final data = twice.single.toStorage();
    expect(data.keys.toSet(), {
      'content',
      'normalizedText',
      'keyword',
      'mode',
      'progress',
      'count',
    });
    final restored = DanmakuLearningSample.fromStorage([data]);
    expect(restored.single.content, sample.content);
    expect(restored.single.count, 2);
  });

  test('learning queue has a hard record cap', () {
    var samples = <DanmakuLearningSample>[];
    for (var i = 0; i <= DanmakuLearningSample.maxSamples; i++) {
      samples = DanmakuLearningSample.collect(
        samples,
        DanmakuLearningSample(content: '$i', keyword: '$i', mode: 'exact'),
      );
    }
    expect(samples.length, DanmakuLearningSample.maxSamples);
    expect(samples.first.content, '${DanmakuLearningSample.maxSamples}');
    expect(samples.any((item) => item.content == '0'), isFalse);
  });

  test('learning export includes manual blocks and exact whitelist entries', () {
    const sample = DanmakuLearningSample(
      content: '需要屏蔽的原文',
      keyword: '屏蔽',
      mode: 'contains',
      count: 2,
    );
    final encoded = jsonEncode(
      DanmakuLearningExport.build(
        samples: const [sample],
        whitelist: const ['  正常弹幕  ', '正常弹幕', '', '另一条白名单'],
      ),
    );
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    expect(decoded['schema'], DanmakuLearningExport.schema);
    expect(decoded['whitelist'], ['正常弹幕', '另一条白名单']);
    expect((decoded['samples'] as List).single, {
      'content': '需要屏蔽的原文',
      'normalizedText': '需要屏蔽的原文',
      'keyword': '屏蔽',
      'mode': 'contains',
      'count': 2,
    });
    expect(encoded, isNot(contains('sender')));
    expect(encoded, isNot(contains('cid')));
    expect(encoded, isNot(contains('account')));
  });

  test('new settings and samples survive the existing backup payload', () {
    final config = DanmakuAssistantConfig.defaults().copyWith(
      strictNoiseFilter: true,
      noiseWhitelist: ['hello world'],
      learningSamples: const [
        DanmakuLearningSample(
          content: 'noise',
          keyword: 'noise',
          mode: 'exact',
        ),
      ],
    );
    final restored = DanmakuAssistantConfig.fromStorage(config.toStorage());
    expect(restored.strictNoiseFilter, isTrue);
    expect(restored.noiseWhitelist, ['hello world']);
    expect(restored.learningSamples.single.content, 'noise');
    expect(DanmakuLearningSample.fromStorage([null, {}, 'bad']), isEmpty);
  });

  test('character compaction changes rendering only', () {
    expect(DanmakuSpamDetector.compactDisplay('哈哈哈哈哈'), '哈哈哈');
    expect(DanmakuSpamDetector.compactDisplay('66666'), '666');
    expect(DanmakuSpamDetector.compactDisplay('4.66JJJJJJJJ'), '4.66JJJ');
    expect(
      DanmakuSpamDetector(processSalt: 1).inspect(
        content: 'JJJJJJJJJJJJJJJJJJJJ',
        progress: 0,
        sender: 'a',
        compactCharacterRuns: true,
      ),
      isNull,
    );
    expect(DanmakuSpamDetector.compactDisplay('正常文本？？？？'), '正常文本？？？？');
    final detector = DanmakuSpamDetector(processSalt: 1);
    expect(
      detector.inspect(
        content: '哈哈哈哈哈哈',
        progress: 0,
        sender: 'a',
        compactCharacterRuns: true,
      ),
      isNull,
    );
    expect(
      detector.inspect(
        content: '哈哈哈哈哈哈',
        progress: 1000,
        sender: 'b',
        compactCharacterRuns: true,
      ),
      isNull,
    );
    expect(
      detector
          .inspect(
            content: '哈哈哈哈哈哈',
            progress: 2000,
            sender: 'c',
            compactCharacterRuns: true,
          )
          ?.reason,
      DanmakuSpamReason.globalWindow,
    );
  });

  test(
    'local phrase repetitions do not require the whole message to repeat',
    () {
      final detector = DanmakuSpamDetector(processSalt: 1);
      expect(
        detector
            .inspect(content: '这都喂不饱？我来我来我来', progress: 0, sender: 'a')
            ?.reason,
        DanmakuSpamReason.embeddedPhrase,
      );
      expect(
        detector.inspect(content: '这都喂不饱？我来我来', progress: 0, sender: 'a'),
        isNull,
      );
      expect(
        detector.inspect(content: '真的哈哈哈哈哈', progress: 0, sender: 'a'),
        isNull,
      );
    },
  );

  for (final text in [
    '7分钟',
    '七分钟',
    '三十一分钟',
    '2分钟！！',
    '12分钟热乎',
    '半小时，热乎',
    '40分钟热热能吃',
    '12 minutes ago',
  ]) {
    test('time candidate: $text', () {
      expect(TemplateSpamTracker.classify(text), isNotNull);
    });
  }

  test('normal sentences remain outside the expanded time templates', () {
    expect(TemplateSpamTracker.classify('比赛还剩7分钟'), isNull);
    expect(TemplateSpamTracker.classify('我5分钟前刚看到'), isNull);
    expect(TemplateSpamTracker.classify('12小时前'), isNotNull);
    expect(
      TemplateSpamTracker.classify('12 minutes ago')?.templateKey,
      TemplateSpamTracker.classify('12分钟前')?.templateKey,
    );
    expect(
      TemplateSpamTracker.classify('半小时')?.templateKey,
      TemplateSpamTracker.classify('30分钟')?.templateKey,
    );
    expect(
      TemplateSpamTracker.classify('1小时')?.templateKey,
      isNot(TemplateSpamTracker.classify('30分钟')?.templateKey),
    );
  });

  test('short symbol variants require a shared window, never a single hit', () {
    final tracker = TemplateSpamTracker(processSalt: 1);
    expect(
      tracker.inspect(
        cid: 1,
        eventId: '1',
        content: '/',
        progress: 0,
        sender: 'a',
      ),
      isNull,
    );
    expect(
      tracker.inspect(
        cid: 1,
        eventId: '2',
        content: '.0',
        progress: 1000,
        sender: 'b',
      ),
      isNull,
    );
    expect(
      tracker
          .inspect(
            cid: 1,
            eventId: '3',
            content: '←+1',
            progress: 2000,
            sender: 'c',
          )
          ?.reason,
      TemplateSpamReason.symbolFragment,
    );
    expect(TemplateSpamTracker.classify('这是引用《书名》'), isNull);
    expect(TemplateSpamTracker.classify('233'), isNull);
  });
}
