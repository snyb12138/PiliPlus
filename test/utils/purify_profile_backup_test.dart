import 'package:PiliPlus/utils/purify_profile_backup.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> validProfile({Map<String, dynamic>? settings}) => {
    'schema': PurifyProfileCodec.schema,
    'version': PurifyProfileCodec.version,
    'exportTime': '2026-11-05T09:00:00.000Z',
    'settings':
        settings ??
        {
          PurifyProfileCodec.settingSection: <String, dynamic>{
            SettingBoxKey.antiGoodsReply: true,
          },
          PurifyProfileCodec.videoSection: <String, dynamic>{
            VideoBoxKey.playSpeedDefault: 1.25,
          },
        },
    'purify': <String, dynamic>{
      'schema': 'piliplus-purify',
      'version': 4,
    },
  };

  test('profile codec preserves settings and purify data', () {
    final decoded = PurifyProfileCodec.decode(validProfile());

    expect(
      decoded.settings[PurifyProfileCodec.settingSection],
      containsPair(SettingBoxKey.antiGoodsReply, true),
    );
    expect(
      decoded.settings[PurifyProfileCodec.videoSection],
      containsPair(VideoBoxKey.playSpeedDefault, 1.25),
    );
    expect(decoded.purify['version'], 4);
    expect(decoded.exportTime, DateTime.utc(2026, 11, 5, 9));
  });

  test('sensitive and device-specific fields are excluded', () {
    final decoded = PurifyProfileCodec.decode(
      validProfile(
        settings: {
          PurifyProfileCodec.settingSection: <String, dynamic>{
            SettingBoxKey.antiGoodsReply: true,
            SettingBoxKey.webdavPassword: 'secret',
            SettingBoxKey.buvid: 'device-id',
            SettingBoxKey.downloadPath: '/device/path',
            SettingBoxKey.purifyBackupDirectory: '/backup/path',
          },
          PurifyProfileCodec.videoSection: <String, dynamic>{},
        },
      ),
    );
    final setting =
        decoded.settings[PurifyProfileCodec.settingSection]
            as Map<String, dynamic>;

    expect(setting[SettingBoxKey.antiGoodsReply], isTrue);
    expect(setting.containsKey(SettingBoxKey.webdavPassword), isFalse);
    expect(setting.containsKey(SettingBoxKey.buvid), isFalse);
    expect(setting.containsKey(SettingBoxKey.downloadPath), isFalse);
    expect(
      setting.containsKey(SettingBoxKey.purifyBackupDirectory),
      isFalse,
    );
  });

  test('invalid profile is rejected before settings can be applied', () {
    expect(
      () => PurifyProfileCodec.decode({
        ...validProfile(),
        'schema': 'unexpected',
      }),
      throwsFormatException,
    );
    expect(
      () => PurifyProfileCodec.decode({
        ...validProfile(),
        'settings': <String, dynamic>{},
      }),
      throwsFormatException,
    );
  });

  test('newer profile version requires a newer app', () {
    expect(
      () => PurifyProfileCodec.decode({
        ...validProfile(),
        'version': PurifyProfileCodec.version + 1,
      }),
      throwsFormatException,
    );
  });
}
