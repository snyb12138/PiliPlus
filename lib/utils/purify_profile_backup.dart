// Backup watchers intentionally live for the entire application process.
// ignore_for_file: cancel_subscriptions

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/utils/config_archive.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/recommend_filter.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class PurifyProfileData {
  const PurifyProfileData({
    required this.settings,
    required this.purify,
    required this.exportTime,
  });

  final Map<String, dynamic> settings;
  final Map<String, dynamic> purify;
  final DateTime? exportTime;
}

class PurifyProfileReadResult {
  const PurifyProfileReadResult({
    required this.data,
    required this.usedPrevious,
  });

  final PurifyProfileData data;
  final bool usedPrevious;
}

class PurifyProfileDirectoryAccessException implements Exception {
  const PurifyProfileDirectoryAccessException(this.directory, this.cause);

  final String directory;
  final FileSystemException cause;

  @override
  String toString() => '备份目录权限已失效，请重新选择该目录后再试';
}

abstract final class PurifyProfileCodec {
  static const String schema = 'piliplus-purify-profile';
  static const int version = 1;
  static const String settingSection = 'setting';
  static const String videoSection = 'video';

  static const Set<String> excludedSettingKeys = {
    SettingBoxKey.webdavUri,
    SettingBoxKey.webdavUsername,
    SettingBoxKey.webdavPassword,
    SettingBoxKey.webdavDirectory,
    SettingBoxKey.enableSystemProxy,
    SettingBoxKey.systemProxyHost,
    SettingBoxKey.systemProxyPort,
    SettingBoxKey.downloadPath,
    SettingBoxKey.imageSavePath,
    SettingBoxKey.appFont,
    SettingBoxKey.buvid,
    SettingBoxKey.windowSize,
    SettingBoxKey.windowPosition,
    SettingBoxKey.isWindowMaximized,
    SettingBoxKey.purifyBackupDirectory,
    SettingBoxKey.purifyBackupAuto,
    SettingBoxKey.purifyBackupLastAt,
  };

  static Map<String, dynamic> sanitizeSettings(Map raw) {
    final setting = _stringMap(raw[settingSection], '通用设置');
    final video = _stringMap(raw[videoSection], '视频设置');
    setting.removeWhere((key, _) => excludedSettingKeys.contains(key));
    return <String, dynamic>{
      settingSection: setting,
      videoSection: video,
    };
  }

  static PurifyProfileData decode(Object? raw) {
    final root = _stringMap(raw, '配置方案');
    if (root['schema'] != schema) {
      throw const FormatException('不是 PiliPlus 净化版配置方案');
    }
    final fileVersion = root['version'];
    if (fileVersion is! int || fileVersion < 1) {
      throw const FormatException('配置方案版本无效');
    }
    if (fileVersion > version) {
      throw FormatException('配置方案版本过新（$fileVersion），请升级应用后再恢复');
    }
    final settings = sanitizeSettings(
      _stringMap(root['settings'], '设置数据'),
    );
    final purify = _stringMap(root['purify'], '净化数据');
    final exportTime = switch (root['exportTime']) {
      final String value => DateTime.tryParse(value),
      _ => null,
    };
    return PurifyProfileData(
      settings: settings,
      purify: purify,
      exportTime: exportTime,
    );
  }

  static Map<String, dynamic> _stringMap(Object? raw, String name) {
    if (raw is! Map) throw FormatException('$name格式不正确');
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) throw FormatException('$name包含无效字段');
      result[entry.key as String] = entry.value;
    }
    return result;
  }
}

abstract final class PurifyProfileBackup {
  static const String fileName = 'PiliPlus-Purify-profile.json';
  static const String previousFileName =
      'PiliPlus-Purify-profile.previous.json';

  static const Duration _debounce = Duration(seconds: 2);
  static const Set<String> _localCacheKeys = {
    LocalCacheKey.blackMids,
    LocalCacheKey.danmakuFilterRules,
    LocalCacheKey.danmakuAssistantConfig,
    LocalCacheKey.replyPurifyConfig,
    LocalCacheKey.purifyV4BrowserExtension,
  };
  static const Set<String> _metadataKeys = {
    SettingBoxKey.purifyBackupDirectory,
    SettingBoxKey.purifyBackupAuto,
    SettingBoxKey.purifyBackupLastAt,
  };

  static Timer? _timer;
  static bool _initialized = false;
  static bool _suspended = false;
  static bool _writing = false;

  static String get directory => Pref.purifyBackupDirectory;
  static bool get autoBackup => Pref.purifyBackupAuto;
  static String get lastBackupAt => Pref.purifyBackupLastAt;
  static String? get profilePath => directory.isEmpty
      ? null
      : path.join(directory, fileName);

  static void init() {
    if (_initialized) return;
    _initialized = true;
    GStorage.setting.watch().listen((event) {
      if (!_metadataKeys.contains(event.key)) _scheduleBackup();
    });
    GStorage.video.watch().listen((_) {
      _scheduleBackup();
    });
    GStorage.localCache.watch().listen((event) {
      if (_localCacheKeys.contains(event.key)) _scheduleBackup();
    });
  }

  static Future<void> setDirectory(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw ArgumentError('备份目录不能为空');
    final normalized = path.normalize(trimmed);
    _timer?.cancel();
    await Future.wait([
      GStorage.setting.put(SettingBoxKey.purifyBackupDirectory, normalized),
      GStorage.setting.put(SettingBoxKey.purifyBackupAuto, false),
      GStorage.setting.delete(SettingBoxKey.purifyBackupLastAt),
    ]);
  }

  static Future<void> setAutoBackup(bool value) async {
    if (value && directory.isEmpty) {
      throw StateError('请先选择备份目录');
    }
    await GStorage.setting.put(SettingBoxKey.purifyBackupAuto, value);
  }

  static bool hasBackup() {
    final target = profilePath;
    if (target == null) return false;
    if (File(target).existsSync()) return true;
    return File(path.join(directory, previousFileName)).existsSync();
  }

  static Future<void> backupNow() async {
    if (_writing) return;
    final targetPath = profilePath;
    if (targetPath == null) throw StateError('请先选择备份目录');
    _timer?.cancel();
    _writing = true;
    try {
      final folder = Directory(directory);
      if (!folder.existsSync()) await folder.create(recursive: true);

      final settings = PurifyProfileCodec.sanitizeSettings(
        jsonDecode(GStorage.exportAllSettings()) as Map,
      );
      final now = DateTime.now();
      final profile = <String, dynamic>{
        'schema': PurifyProfileCodec.schema,
        'version': PurifyProfileCodec.version,
        'appName': Constants.appName,
        'appVersion': BuildConfig.versionName,
        'versionCode': BuildConfig.versionCode,
        'commitHash': BuildConfig.commitHash,
        'platform': DeviceUtils.platformName,
        'exportTime': now.toIso8601String(),
        'settings': settings,
        'purify': ConfigArchive.exportPurifyConfig(),
      };

      final target = File(targetPath);
      final temporary = File('$targetPath.tmp');
      final previous = File(path.join(directory, previousFileName));
      await temporary.writeAsString(
        Utils.jsonEncoder.convert(profile),
        flush: true,
      );
      PurifyProfileCodec.decode(jsonDecode(await temporary.readAsString()));

      if (previous.existsSync()) await previous.delete();
      if (target.existsSync()) await target.rename(previous.path);
      try {
        await temporary.rename(target.path);
      } catch (_) {
        if (!target.existsSync() && previous.existsSync()) {
          await previous.rename(target.path);
        }
        rethrow;
      }
      await GStorage.setting.put(
        SettingBoxKey.purifyBackupLastAt,
        now.toIso8601String(),
      );
    } finally {
      _writing = false;
    }
  }

  static Future<PurifyProfileReadResult> readBackup() async {
    if (directory.isEmpty) throw StateError('请先选择备份目录');
    return readFromDirectory(directory);
  }

  @visibleForTesting
  static Future<PurifyProfileReadResult> readFromDirectory(
    String directory,
  ) async {
    final target = File(path.join(directory, fileName));
    final previous = File(path.join(directory, previousFileName));
    Object? currentError;
    try {
      final data = await _readProfileFile(target);
      return PurifyProfileReadResult(data: data, usedPrevious: false);
    } on PathNotFoundException {
      // Try the retained previous version below.
    } on FormatException catch (error) {
      currentError = error;
    }
    try {
      final data = await _readProfileFile(previous);
      return PurifyProfileReadResult(data: data, usedPrevious: true);
    } on PathNotFoundException {
      // Report the format error from the current file, when present.
    } on FormatException catch (error) {
      currentError ??= error;
    }
    if (currentError != null) throw FormatException('备份文件损坏：$currentError');
    throw const FileSystemException('所选目录中没有配置方案备份');
  }

  static Future<PurifyProfileData> _readProfileFile(File file) async {
    try {
      return PurifyProfileCodec.decode(jsonDecode(await file.readAsString()));
    } on FileSystemException catch (error) {
      final errorCode = error.osError?.errorCode;
      if (errorCode == 1 || errorCode == 13) {
        throw PurifyProfileDirectoryAccessException(
          file.parent.path,
          error,
        );
      }
      rethrow;
    }
  }

  static Future<PurifyProfileReadResult> restore() async {
    final result = await readBackup();
    final rollbackSettings =
        jsonDecode(GStorage.exportAllSettings()) as Map<String, dynamic>;
    final rollbackPurify = ConfigArchive.exportPurifyConfig();
    final preservedLocalSettings = <String, dynamic>{};
    for (final key in PurifyProfileCodec.excludedSettingKeys) {
      if (GStorage.setting.containsKey(key)) {
        preservedLocalSettings[key] = GStorage.setting.get(key);
      }
    }
    final preservedDirectory = directory;
    final preservedAutoBackup = autoBackup;
    final preservedLastBackupAt = lastBackupAt;
    final restoredBackupAt = preservedLastBackupAt.isNotEmpty
        ? preservedLastBackupAt
        : result.data.exportTime?.toIso8601String() ?? '';
    _timer?.cancel();
    _suspended = true;
    try {
      try {
        await GStorage.importAllJsonSettings(result.data.settings);
        await GStorage.setting.putAll(preservedLocalSettings);
        await Future.wait([
          GStorage.setting.put(
            SettingBoxKey.purifyBackupDirectory,
            preservedDirectory,
          ),
          GStorage.setting.put(
            SettingBoxKey.purifyBackupAuto,
            preservedAutoBackup,
          ),
          if (restoredBackupAt.isNotEmpty)
            GStorage.setting.put(
              SettingBoxKey.purifyBackupLastAt,
              restoredBackupAt,
            ),
        ]);
        await ConfigArchive.importPurifyConfig(result.data.purify);
      } catch (error, stackTrace) {
        try {
          await GStorage.importAllJsonSettings(rollbackSettings);
          await ConfigArchive.importPurifyConfig(rollbackPurify);
        } catch (rollbackError, rollbackStackTrace) {
          if (kDebugMode) {
            debugPrint('Purify profile rollback failed: $rollbackError');
            debugPrintStack(stackTrace: rollbackStackTrace);
          }
        }
        _reloadRuntimeSettings();
        Error.throwWithStackTrace(error, stackTrace);
      }
      _reloadRuntimeSettings();
      return result;
    } finally {
      await Future<void>.delayed(Duration.zero);
      _suspended = false;
    }
  }

  static void _reloadRuntimeSettings() {
    ReplyGrpc.antiGoodsReply = Pref.antiGoodsReply;
    ReplyGrpc.blockAtOnlyReply = Pref.blockAtOnlyReply;
    ReplyGrpc.blockReplyAtCount = Pref.blockReplyAtCount;
    RecommendFilter.reloadFromPrefs();
  }

  static void _scheduleBackup() {
    if (_suspended || _writing || !autoBackup || directory.isEmpty) return;
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      unawaited(
        backupNow().catchError((Object error, StackTrace stackTrace) {
          if (kDebugMode) {
            debugPrint('Purify profile auto backup failed: $error');
            debugPrintStack(stackTrace: stackTrace);
          }
        }),
      );
    });
  }
}
