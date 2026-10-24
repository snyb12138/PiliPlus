import 'package:PiliPlus/models/user/reply_ai_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('short conversational comments are not classified', () {
    final result = ReplyAiDetector.assess('这波操作确实厉害，我也学会了');
    expect(result.score, 0);
    expect(result.matches(ReplyAiFilterLevel.balanced), isFalse);
  });

  test('explicit model disclosure matches conservative mode', () {
    final result = ReplyAiDetector.assess('作为一个 AI 语言模型，我无法判断视频中的真实情况。');
    expect(result.signals, contains(ReplyAiSignal.modelDisclosure));
    expect(result.matches(ReplyAiFilterLevel.conservative), isTrue);
  });

  test('template-like long explanation matches balanced mode only', () {
    const message =
        '只要把实力隐藏起来，装作实力不行但又喜欢玩游戏的玩家，'
        '系统就会识别出来，然后把你放进舒适的匹配池里面。'
        '这并不是演，而是骗过了匹配机制，把一个什么都懂的玩家顶替掉原先的玩家，'
        '必要的时候也可以发挥出该有的作用。';

    final result = ReplyAiDetector.assess(message);
    expect(result.signals, contains(ReplyAiSignal.contrastTemplate));
    expect(result.signals, contains(ReplyAiSignal.causalChain));
    expect(result.matches(ReplyAiFilterLevel.balanced), isTrue);
    expect(result.matches(ReplyAiFilterLevel.conservative), isFalse);
  });

  test('length alone is insufficient to classify a comment', () {
    final message = List.filled(18, '这一段是玩家对操作细节的具体复盘').join('，');
    final result = ReplyAiDetector.assess(message);
    expect(result.matches(ReplyAiFilterLevel.balanced), isFalse);
  });
}
