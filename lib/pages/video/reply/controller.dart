import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, ReplyInfo;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/user/reply_density_detector.dart';
import 'package:PiliPlus/models_new/dynamic/dyn_mention/item.dart';
import 'package:PiliPlus/pages/common/reply/fold/reply_fold_mixin.dart';
import 'package:PiliPlus/pages/common/reply/reply_controller.dart';
import 'package:PiliPlus/pages/common/reply/vote/reply_vote_mixin.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/reply_reply/view.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/reply_scheme_helper.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart' show BoxConstraints, WidgetsBinding;
import 'package:get/get.dart';

class VideoReplyController extends ReplyController<MainListReply>
    with
        ReplyVoteMixin,
        GetSingleTickerProviderStateMixin,
        ReplyLocateMixin,
        MainReplyLocateMixin,
        BaseReplyFoldMixin<MainListReply>,
        ReplyFoldMixin {
  VideoReplyController({
    required this.heroTag,
  });
  late final isPugv = videoCtr.videoType == .pugv;

  @override
  int get oid => isPugv ? videoCtr.epId! : videoCtr.aid;

  @override
  int get replyType => videoCtr.videoType.replyType;

  final String heroTag;
  late final videoCtr = Get.find<VideoDetailController>(tag: heroTag);
  final Map<int, ReplyPurifyVideoSession> _purifySessions = {};
  ReplyPurifyVideoSession get purifySession {
    final videoId = oid;
    return _purifySessions.putIfAbsent(
      videoId,
      () => ReplyPurifyVideoSession(videoId: videoId),
    );
  }

  void _recordBlockedReply(ReplyInfo reply, List<String> reasons) {
    purifySession.recordPreview(
      ReplyPurifyPreviewEntry(
        replyId: reply.id.toInt(),
        rootId: reply.root.toInt(),
        parentId: reply.parent.toInt(),
        mid: reply.mid.toInt(),
        name: reply.member.name,
        message: reply.content.message,
        action: ReplyPurifyPreviewAction.blocked,
        reasons: List.unmodifiable(reasons),
      ),
    );
  }

  @override
  void onPurifyBlockedReply(ReplyInfo reply, List<String> reasons) =>
      _recordBlockedReply(reply, reasons);

  @override
  bool isPurifyReplyIgnored(int replyId) =>
      purifySession.isIgnored(replyId);

  MentionItem? get mentionItem {
    if (videoCtr.isUgc) {
      try {
        return videoCtr.ugcIntroCtr.videoDetail.value.owner?.mentionItem;
      } catch (_) {
        if (kDebugMode) rethrow;
      }
    }
    return null;
  }

  @override
  dynamic get sourceId => IdUtils.av2bv(videoCtr.aid);

  @override
  void onAnimRootReply(ReplyInfo rootReply) {
    if (args[secondRpIdKey] case final int secondRpId) {
      clearTargetRootRpId();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => replyReply(rootReply, secondRpId),
      );
    } else {
      super.onAnimRootReply(rootReply);
    }
  }

  void replyReply(ReplyInfo replyItem, int? id) {
    videoCtr.childKey.currentState?.showBottomSheet(
      constraints: const BoxConstraints(),
      (context) => VideoReplyReplyPanel(
        id: id,
        oid: replyItem.oid.toInt(),
        rpid: replyItem.id.toInt(),
        firstFloor: replyItem.replyControl.isNote ? null : replyItem,
        replyType: videoCtr.videoType.replyType,
        isVideoDetail: true,
        isNested: videoCtr.scrollKey.currentContext != null,
        upMid: upMid,
        purifySession: purifySession,
      ),
    );
  }

  @override
  Future<LoadingState<MainListReply>> customGetData() => ReplyGrpc.mainList(
    oid: oid,
    rpid: rootRpId,
    type: replyType,
    mode: mode,
    cursorNext: cursorNext,
    offset: paginationReply?.nextOffset,
    onBlocked: _recordBlockedReply,
    isIgnored: purifySession.isIgnored,
  );

  @override
  Future<void> onRefresh() {
    _purifySessions[oid]?.clearPreview();
    return super.onRefresh();
  }

  @override
  void onClose() {
    for (final session in _purifySessions.values) {
      session.dispose();
    }
    _purifySessions.clear();
    super.onClose();
  }
}
