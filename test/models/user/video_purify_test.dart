import 'package:PiliPlus/models/user/video_purify.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video purify is opt-in by default', () {
    const config = VideoPurifyConfig();

    expect(config.enabled, isFalse);
    expect(config.applyToRelatedVideos, isTrue);
    expect(config.exemptFollowedUploaders, isTrue);
  });

  test('storage round trip preserves keyword options', () {
    const config = VideoPurifyConfig(
      keywordPattern: '抽奖|带货',
      applyToRelatedVideos: false,
      exemptFollowedUploaders: false,
    );

    final restored = VideoPurifyConfig.fromStorage(config.toStorage());
    expect(restored.keywordPattern, '抽奖|带货');
    expect(restored.applyToRelatedVideos, isFalse);
    expect(restored.exemptFollowedUploaders, isFalse);
  });

  test('invalid regular expression is rejected before import', () {
    expect(
      () => VideoPurifyConfig.fromStorage({
        'keywordPattern': '[',
      }),
      throwsFormatException,
    );
  });

  test('copyWith only changes the selected option', () {
    const config = VideoPurifyConfig(keywordPattern: '测试');
    final changed = config.copyWith(applyToRelatedVideos: false);

    expect(changed.keywordPattern, '测试');
    expect(changed.applyToRelatedVideos, isFalse);
    expect(changed.exemptFollowedUploaders, isTrue);
  });
}
