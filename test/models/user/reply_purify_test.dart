import 'package:PiliPlus/models/user/reply_purify.dart';
import 'package:PiliPlus/models/user/reply_ai_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reply purify is opt-in by default', () {
    final config = ReplyPurifyConfig.defaults();
    expect(config.mutedUsers, isEmpty);
    expect(config.contains(123), isFalse);
    expect(config.aiFilterLevel, ReplyAiFilterLevel.off);
    expect(config.trustedAiUsers, isEmpty);
    expect(config.markedUsers, isEmpty);
    expect(config.centerMode, ReplyPurifyCenterMode.expanded);
  });

  test('add and remove only affect the selected uid', () {
    final config = ReplyPurifyConfig.defaults().addUser(123, name: '测试账号');
    expect(config.contains(123), isTrue);
    expect(config.contains(456), isFalse);
    expect(config.mutedUsers[123]?.name, '测试账号');

    final restored = config.removeUser(123);
    expect(restored.contains(123), isFalse);
    expect(config.contains(123), isTrue);
  });

  test('storage round trip preserves uid and display name', () {
    final config = ReplyPurifyConfig.defaults()
        .addUser(123, name: '账号 A')
        .addUser(456);

    final restored = ReplyPurifyConfig.fromStorage(config.toStorage());
    expect(restored.mutedUsers.keys, containsAll(<int>[123, 456]));
    expect(restored.mutedUsers[123]?.name, '账号 A');
    expect(restored.mutedUsers[456]?.name, isEmpty);
  });

  test('malformed storage entries are ignored safely', () {
    final restored = ReplyPurifyConfig.fromStorage({
      'mutedUsers': [
        {'mid': '123', 'name': '有效'},
        {'mid': 0, 'name': '无效'},
        {'name': '缺少 UID'},
        'invalid',
      ],
    });

    expect(restored.mutedUsers.length, 1);
    expect(restored.mutedUsers[123]?.name, '有效');
  });

  test('AI filter settings round trip and remain backward compatible', () {
    final config = ReplyPurifyConfig.defaults()
        .setAiFilterLevel(ReplyAiFilterLevel.balanced)
        .trustAiUser(789, name: '可信账号');

    final restored = ReplyPurifyConfig.fromStorage(config.toStorage());
    expect(restored.aiFilterLevel, ReplyAiFilterLevel.balanced);
    expect(restored.trustedAiUsers[789]?.name, '可信账号');

    final legacy = ReplyPurifyConfig.fromStorage({
      'version': 1,
      'mutedUsers': const [],
    });
    expect(legacy.aiFilterLevel, ReplyAiFilterLevel.off);
    expect(legacy.trustedAiUsers, isEmpty);
  });

  test('marked users and hub mode survive storage round trip', () {
    final config = ReplyPurifyConfig.defaults()
        .markUser(321, name: '待检查账号')
        .setCenterMode(ReplyPurifyCenterMode.hidden);

    final restored = ReplyPurifyConfig.fromStorage(config.toStorage());
    expect(restored.markedUsers[321]?.name, '待检查账号');
    expect(restored.centerMode, ReplyPurifyCenterMode.hidden);
    expect(restored.isMarked(321), isTrue);
    expect(restored.unmarkUser(321).isMarked(321), isFalse);
  });

  test('trusted AI users can be removed without changing muted users', () {
    final config = ReplyPurifyConfig.defaults().addUser(123).trustAiUser(456);
    final restored = config.untrustAiUser(456);

    expect(restored.contains(123), isTrue);
    expect(restored.trustsAiUser(456), isFalse);
  });
}
