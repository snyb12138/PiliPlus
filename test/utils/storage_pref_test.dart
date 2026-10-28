import 'dart:io';

import 'package:PiliPlus/models/common/sponsor_block/segment_type.dart';
import 'package:PiliPlus/models/common/sponsor_block/skip_type.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-pref-test-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
  });

  setUp(() => GStorage.setting.clear());

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('SponsorBlock setting recovery', () {
    test('invalid block setting entries fall back without losing valid ones', () async {
      await GStorage.setting.put(SettingBoxKey.blockSettings, [
        SkipType.alwaysSkip.index,
        'invalid',
        -1,
        SkipType.values.length,
      ]);

      final settings = Pref.blockSettings;

      expect(settings, hasLength(SegmentType.values.length));
      expect(settings.first.second, SkipType.alwaysSkip);
      expect(
        settings.skip(1).map((item) => item.second),
        everyElement(SkipType.skipOnce),
      );
    });

    test('oversized block setting lists reset to safe defaults', () async {
      await GStorage.setting.put(
        SettingBoxKey.blockSettings,
        List.filled(SegmentType.values.length + 1, SkipType.alwaysSkip.index),
      );

      expect(
        Pref.blockSettings.map((item) => item.second),
        everyElement(SkipType.skipOnce),
      );
    });

    test('invalid and missing block colors fall back per category', () async {
      await GStorage.setting.put(SettingBoxKey.blockColor, [
        '112233',
        '',
        'GGGGGG',
        123,
        '12345678',
      ]);

      final colors = Pref.blockColor;

      expect(colors, hasLength(SegmentType.values.length));
      expect(colors.first.toARGB32(), 0xFF112233);
      for (var i = 1; i < colors.length; i++) {
        expect(colors[i], SegmentType.values[i].color);
      }
    });

    test('oversized block color lists reset to category defaults', () async {
      await GStorage.setting.put(
        SettingBoxKey.blockColor,
        List.filled(SegmentType.values.length + 1, '112233'),
      );

      expect(
        Pref.blockColor,
        SegmentType.values.map((item) => item.color).toList(),
      );
    });
  });
}
