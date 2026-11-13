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
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

class PurifyBackupDirectorySelection {
  const PurifyBackupDirectorySelection({
    required this.uri,
    required this.label,
  });

  final String uri;
  final String label;
}

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
    SettingBoxKey.purifyBackupDirectoryLabel,
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
  static const MethodChannel _androidChannel = MethodChannel(
    'com.snyb12138.piliplus.purify/profile_backup',
  );

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
    SettingBoxKey.purifyBackupDirectoryLabel,
    SettingBoxKey.purifyBackupAuto,
    SettingBoxKey.purifyBackupLastAt,
  };

  static Timer? _timer;
  static bool _initialized = false;
  static bool _suspended = false;
  static bool _writing = false;

  static String get directory => Pref.purifyBackupDirectory;
  static String get directoryLabel => Pref.purifyBackupDirectoryLabel;
  static bool get autoBackup => Pref.purifyBackupAuto;
  static String get lastBackupAt => Pref.purifyBackupLastAt;
  static bool get needsDirectoryReselection =>
      Platform.isAndroid &&
      directory.isNotEmpty &&
      !directory.startsWith('content://');
  static String? get profilePath => Platform.isAndroid || directory.isEmpty
      ? null
      : path.join(directory, fileName);

  static Future<PurifyBackupDirectorySelection?> pickAndroidDirectory() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('SAF directory selection is Android-only');
    }
    final result = await _androidChannel.invokeMapMethod<String, dynamic>(
      'pickDirectory',
      <String, dynamic>{
        if (directory.startsWith('content://')) 'initialUri': directory,
      },
    );
    if (result == null) return null;
    final uri = result['uri'];
    final label = result['label'];
    if (uri is! String || uri.isEmpty) {
      throw const FormatException('系统没有返回有效的备份目录');
    }
    return PurifyBackupDirectorySelection(
      uri: uri,
      label: label is String && label.isNotEmpty ? label : '已授权目录',
    );
  }

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

  static Future<void> setDirectory(
    String value, {
    String? displayName,
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw ArgumentError('备份目录不能为空');
    final normalized = Platform.isAndroid && trimmed.startsWith('content://')
        ? trimmed
        : path.normalize(trimmed);
    _timer?.cancel();
    await Future.wait([
      GStorage.setting.put(SettingBoxKey.purifyBackupDirectory, normalized),
      if (displayName != null)
        GStorage.setting.put(
          SettingBoxKey.purifyBackupDirectoryLabel,
          displayName,
        )
      else
        GStorage.setting.delete(SettingBoxKey.purifyBackupDirectoryLabel),
      GStorage.setting.put(SettingBoxKey.purifyBackupAuto, false),
      GStorage.setting.delete(SettingBoxKey.purifyBackupLastAt),
    ]);
  }

  static Future<void> setAutoBackup(bool value) async {
    if (value && directory.isEmpty) {
      throw StateError('请先选择备份目录');
    }
    if (value && needsDirectoryReselection) {
      throw StateError('请重新授权 Android 备份目录');
    }
    await GStorage.setting.put(SettingBoxKey.purifyBackupAuto, value);
  }

  static Future<bool> hasBackup() async {
    if (directory.isEmpty || needsDirectoryReselection) return false;
    if (Platform.isAndroid) {
      try {
        return await _androidChannel.invokeMethod<bool>(
              'hasBackup',
              <String, dynamic>{
                'directoryUri': directory,
                'targetName': fileName,
                'previousName': previousFileName,
              },
            ) ??
            false;
      } on PlatformException catch (error) {
        _throwAndroidStorageError(error);
      }
    }
    final target = profilePath!;
    if (File(target).existsSync()) return true;
    return File(path.join(directory, previousFileName)).existsSync();
  }

  static Future<void> backupNow() async {
    if (_writing) return;
    if (directory.isEmpty) throw StateError('请先选择备份目录');
    if (needsDirectoryReselection) {
      throw StateError('旧备份目录没有 Android 写入授权，请重新选择目录');
    }
    _timer?.cancel();
    _writing = true;
    try {
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
      final encoded = Utils.jsonEncoder.convert(profile);
      PurifyProfileCodec.decode(jsonDecode(encoded));

      if (Platform.isAndroid) {
        try {
          await _androidChannel.invokeMethod<bool>(
            'writeBackup',
            <String, dynamic>{
              'directoryUri': directory,
              'targetName': fileName,
              'previousName': previousFileName,
              'bytes': Uint8List.fromList(utf8.encode(encoded)),
            },
          );
        } on PlatformException catch (error) {
          _throwAndroidStorageError(error);
        }
      } else {
        final targetPath = profilePath!;
        final folder = Directory(directory);
        if (!folder.existsSync()) await folder.create(recursive: true);

        final target = File(targetPath);
        final temporary = File('$targetPath.tmp');
        final previous = File(path.join(directory, previousFileName));
        await temporary.writeAsString(encoded, flush: true);
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
    if (needsDirectoryReselection) {
      throw StateError('旧备份目录没有 Android 读取授权，请重新选择目录');
    }
    Object? currentError;
    final target = await _readBackupFile(fileName);
    if (target != null) {
      try {
        final data = PurifyProfileCodec.decode(
          jsonDecode(utf8.decode(target)),
        );
        return PurifyProfileReadResult(data: data, usedPrevious: false);
      } catch (e) {
        currentError = e;
      }
    }
    final previous = await _readBackupFile(previousFileName);
    if (previous != null) {
      try {
        final data = PurifyProfileCodec.decode(
          jsonDecode(utf8.decode(previous)),
        );
        return PurifyProfileReadResult(data: data, usedPrevious: true);
      } catch (e) {
        currentError ??= e;
      }
    }
    if (currentError != null) throw FormatException('备份文件损坏：$currentError');
    throw const FileSystemException('所选目录中没有配置方案备份');
  }

  static Future<Uint8List?> _readBackupFile(String name) async {
    if (Platform.isAndroid) {
      try {
        return await _androidChannel.invokeMethod<Uint8List>(
          'readFile',
          <String, dynamic>{
            'directoryUri': directory,
            'name': name,
          },
        );
      } on PlatformException catch (error) {
        _throwAndroidStorageError(error);
      }
    }
    final file = File(path.join(directory, name));
    return file.existsSync() ? file.readAsBytes() : null;
  }

  static Never _throwAndroidStorageError(PlatformException error) {
    throw StateError(
      'Android 备份目录不可访问，请重新选择目录'
      '${error.message == null ? '' : '：${error.message}'}',
    );
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
    if (_suspended ||
        _writing ||
        !autoBackup ||
        directory.isEmpty ||
        needsDirectoryReselection) {
      return;
    }
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
