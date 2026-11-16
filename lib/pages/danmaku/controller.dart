import 'dart:collection';
import 'dart:io' show File;

import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliPlus/grpc/dm.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/user/danmaku_assistant.dart';
import 'package:PiliPlus/models/user/danmaku_spam/detector.dart';
import 'package:PiliPlus/models/user/danmaku_spam/noise_policy.dart';
import 'package:PiliPlus/models/user/danmaku_spam/template_tracker.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/danmaku_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:path/path.dart' as path;

class PlDanmakuController {
  PlDanmakuController(this._cid, this._plPlayerController, this._isFileSource)
    : _mergeDanmaku = _plPlayerController.mergeDanmaku;

  final int _cid;
  final PlPlayerController _plPlayerController;
  final bool _mergeDanmaku;
  final bool _isFileSource;

  late final _isLogin = Accounts.main.isLogin;

  final Map<int, List<DanmakuElem>> _dmSegMap = HashMap();
  final DanmakuSpamDetector _spamDetector = DanmakuSpamDetector();
  // 已请求的段落标记
  late final Set<int> _requestedSeg = HashSet();
  int _generation = 0;

  void dispose() {
    _generation++;
    _dmSegMap.clear();
    _requestedSeg.clear();
    _spamDetector.reset(keepAllowances: false);
  }

  void reloadAt(int progress) {
    _generation++;
    _dmSegMap.clear();
    _requestedSeg.clear();
    _spamDetector.reset();
    _fileDmLoaded = false;
    if (_isFileSource) {
      initFileDmIfNeeded();
    } else {
      queryDanmaku(DmUtils.calcSegment(progress));
    }
  }

  Future<void> queryDanmaku(int segmentIndex) async {
    if (_isFileSource) {
      return;
    }
    if (_requestedSeg.contains(segmentIndex)) {
      return;
    }
    _requestedSeg.add(segmentIndex);
    final generation = _generation;
    final res = await DmGrpc.dmSegMobile(
      cid: _cid,
      segmentIndex: segmentIndex + 1,
    );

    if (generation != _generation) return;

    if (res case Success(:final response)) {
      if (response.state == 1) {
        _plPlayerController.dmState.add(_cid);
      }
      handleDanmaku(response.elems, segmentIndex: segmentIndex);
    } else {
      _requestedSeg.remove(segmentIndex);
    }
  }

  void handleDanmaku(List<DanmakuElem> elems, {int? segmentIndex}) {
    if (elems.isEmpty) return;
    final uniques = HashMap<String, DanmakuElem>();
    final samples = <DanmakuAssistantRecord>[];
    final hits = <DanmakuAssistantRecord>[];

    final filters = _plPlayerController.filters;
    final shouldFilter = filters.count != 0;
    final assistant = _plPlayerController.danmakuAssistantConfig;
    final whitelist = assistant.noiseWhitelist
        .map(DanmakuNoisePolicy.key)
        .toSet();
    final orderedElems = elems.length < 2
        ? elems
        : (List<DanmakuElem>.of(elems)
            ..sort((a, b) => a.progress.compareTo(b.progress)));
    const segmentDuration = 360000;
    final isolation = assistant.strictNoiseFilter
        ? DanmakuNoisePolicy.isolatedFlags(
            orderedElems
                .map((item) => (content: item.content, progress: item.progress))
                .toList(growable: false),
            coverageStart: segmentIndex == null
                ? 0
                : segmentIndex * segmentDuration,
            coverageEnd: segmentIndex == null
                ? _plPlayerController.durationInMilliseconds
                : (segmentIndex + 1) * segmentDuration,
          )
        : const <bool?>[];
    for (var index = 0; index < orderedElems.length; index++) {
      final element = orderedElems[index];
      if (_isLogin) {
        element.isSelf = element.midHash == _plPlayerController.midHash;
      }

      if (!element.isSelf) {
        var match = assistant.match(element.content, includeAutomatic: false);
        if (match != null) {
          final record = DanmakuAssistantRecord(
            content: element.content,
            progress: element.progress,
            match: match,
          );
          samples.add(record);
          hits.add(record);
          continue;
        }

        if (shouldFilter && filters.remove(element)) {
          final record = DanmakuAssistantRecord(
            content: element.content,
            progress: element.progress,
            match: const DanmakuAssistantMatch(
              kind: DanmakuAssistantKind.traditionalRule,
              reason: '传统关键词/正则/发送者规则',
            ),
          );
          samples.add(record);
          hits.add(record);
          continue;
        }

        final allowed =
            _plPlayerController.isDanmakuSpamAllowed(element.content) ||
            whitelist.contains(DanmakuNoisePolicy.key(element.content));
        if (!allowed) {
          match = assistant.match(element.content);
          if (match == null && assistant.strictNoiseFilter) {
            final reasons = DanmakuNoisePolicy.reasons(
              element.content,
              isolated: isolation[index],
            );
            if (reasons.isNotEmpty) {
              match = DanmakuAssistantMatch(
                kind: DanmakuAssistantKind.strictNoise,
                reason: '激进过滤：${reasons.join('；')}',
              );
            }
          }
        }

        if (match == null && assistant.blockRepeatedSpam && !allowed) {
          final sender = element.midHash.isEmpty
              ? 'unknown:${element.idStr}'
              : element.midHash;
          final templateSpam = _plPlayerController.danmakuTemplateSpamTracker
              .inspect(
                cid: _cid,
                eventId: element.idStr,
                content: element.content,
                progress: element.progress,
                sender: sender,
              );
          final spam = templateSpam == null
              ? _spamDetector.inspect(
                  content: element.content,
                  progress: element.progress,
                  sender: sender,
                  compactCharacterRuns: true,
                )
              : null;
          if (templateSpam != null) {
            final sameSender =
                templateSpam.sameSenderCountAtHit >=
                TemplateSpamTracker.senderWindowThreshold;
            final countDetail = sameSender
                ? '同一发送者 10 秒内第 '
                      '${templateSpam.sameSenderCountAtHit} 条'
                : '5 秒内第 ${templateSpam.countAtHit} 条';
            final span =
                (templateSpam.windowEndProgress -
                    templateSpam.windowStartProgress) /
                1000;
            match = DanmakuAssistantMatch(
              kind: DanmakuAssistantKind.repeatedSpam,
              reason:
                  '${templateSpam.reason.label}（命中模板：'
                  '${templateSpam.templateKey}，$countDetail，'
                  '跨度 ${span.toStringAsFixed(1)} 秒）',
              countAtHit: templateSpam.countAtHit,
              sameSenderCountAtHit: templateSpam.sameSenderCountAtHit,
              windowStartProgress: templateSpam.windowStartProgress,
              windowEndProgress: templateSpam.windowEndProgress,
              normalizedKey: templateSpam.normalizedText,
              repeatBaseKey: templateSpam.templateKey,
              senderHash: templateSpam.senderHash,
            );
          } else if (spam != null) {
            final countDetail = switch (spam.reason) {
              DanmakuSpamReason.globalWindow => '（5 秒内第 ${spam.countAtHit} 条）',
              DanmakuSpamReason.sameSenderWindow =>
                '（同一发送者 10 秒内第 ${spam.sameSenderCountAtHit} 条）',
              _ => '',
            };
            match = DanmakuAssistantMatch(
              kind: DanmakuAssistantKind.repeatedSpam,
              reason: '${spam.reason.label}$countDetail',
              countAtHit: spam.countAtHit,
              sameSenderCountAtHit: spam.sameSenderCountAtHit,
              windowStartProgress: spam.windowStartProgress,
              windowEndProgress: spam.windowEndProgress,
              normalizedKey: spam.normalizedKey,
              repeatBaseKey: spam.repeatBaseKey,
              senderHash: spam.senderHash,
            );
          }
        }

        final record = DanmakuAssistantRecord(
          content: element.content,
          progress: element.progress,
          match: match,
        );
        samples.add(record);
        if (match != null) {
          hits.add(record);
          continue;
        }

        if (_mergeDanmaku) {
          final elem = uniques[element.content];
          if (elem == null) {
            uniques[element.content] = element..count = 1;
          } else {
            elem.count++;
            continue;
          }
        }
      }

      final int pos = element.progress ~/ 100; //每0.1秒存储一次
      (_dmSegMap[pos] ??= []).add(element);
    }
    _plPlayerController.recordDanmakuAssistantBatch(
      samples: samples,
      hits: hits,
    );
  }

  List<DanmakuElem>? getCurrentDanmaku(int progress) {
    if (_isFileSource) {
      initFileDmIfNeeded();
    } else {
      final int segmentIndex = DmUtils.calcSegment(progress);
      if (!_requestedSeg.contains(segmentIndex)) {
        queryDanmaku(segmentIndex);
        return null;
      }
    }
    return _dmSegMap[progress ~/ 100];
  }

  bool _fileDmLoaded = false;

  void initFileDmIfNeeded() {
    if (_fileDmLoaded) return;
    _fileDmLoaded = true;
    _initFileDm();
  }

  @pragma('vm:notify-debugger-on-exception')
  Future<void> _initFileDm() async {
    final generation = _generation;
    try {
      final file = File(
        path.join(
          (_plPlayerController.dataSource as FileSource).dir,
          PathUtils.danmakuName,
        ),
      );
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();
      if (generation != _generation) return;
      if (bytes.isEmpty) return;
      final elem = DmSegMobileReply.fromBuffer(bytes).elems;
      handleDanmaku(elem);
    } catch (e, s) {
      Utils.reportError(e, s);
    }
  }
}
