import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/grpc/bilibili/pagination.pb.dart';
import 'package:PiliPlus/grpc/grpc_req.dart';
import 'package:PiliPlus/grpc/url.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/user/reply_ai_filter.dart';
import 'package:PiliPlus/models/user/reply_density_detector.dart';
import 'package:PiliPlus/models/user/reply_purify.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:fixnum/fixnum.dart';

abstract final class ReplyGrpc {
  static bool antiGoodsReply = Pref.antiGoodsReply;
  static var blockAtOnlyReply = Pref.blockAtOnlyReply;
  static var blockReplyAtCount = Pref.blockReplyAtCount;
  static RegExp replyRegExp = RegExp(
    Pref.banWordForReply,
    caseSensitive: false,
  );
  static bool enableFilter = replyRegExp.pattern.isNotEmpty;
  static ReplyPurifyConfig replyPurifyConfig = Pref.replyPurifyConfig;
  static final ReplyAiMentionTracker _aiMentionTracker =
      ReplyAiMentionTracker();

  static Future<bool> muteReplyUser(int mid, {String name = ''}) async {
    if (mid <= 0 || replyPurifyConfig.contains(mid)) return false;
    replyPurifyConfig = replyPurifyConfig.addUser(mid, name: name);
    await Pref.setReplyPurifyConfig(replyPurifyConfig);
    return true;
  }

  static Future<bool> unmuteReplyUser(int mid) async {
    if (!replyPurifyConfig.contains(mid)) return false;
    replyPurifyConfig = replyPurifyConfig.removeUser(mid);
    await Pref.setReplyPurifyConfig(replyPurifyConfig);
    return true;
  }

  static Future<void> replaceReplyPurifyConfig(ReplyPurifyConfig config) async {
    replyPurifyConfig = config;
    await Pref.setReplyPurifyConfig(config);
  }

  static Future<void> setAiReplyFilterLevel(ReplyAiFilterLevel level) async {
    await replaceReplyPurifyConfig(replyPurifyConfig.setAiFilterLevel(level));
  }

  static Future<void> trustAiReplyUser(int mid, {String name = ''}) async {
    if (mid <= 0) return;
    await replaceReplyPurifyConfig(
      replyPurifyConfig.trustAiUser(mid, name: name),
    );
  }

  static Future<void> untrustAiReplyUser(int mid) async {
    if (!replyPurifyConfig.trustsAiUser(mid)) return;
    await replaceReplyPurifyConfig(replyPurifyConfig.untrustAiUser(mid));
  }

  static Future<bool> markReplyUser(int mid, {String name = ''}) async {
    if (mid <= 0 || replyPurifyConfig.isMarked(mid)) return false;
    await replaceReplyPurifyConfig(
      replyPurifyConfig.markUser(mid, name: name),
    );
    return true;
  }

  static Future<bool> unmarkReplyUser(int mid) async {
    if (!replyPurifyConfig.isMarked(mid)) return false;
    await replaceReplyPurifyConfig(replyPurifyConfig.unmarkUser(mid));
    return true;
  }

  static Future<void> setPurifyCenterMode(
    ReplyPurifyCenterMode mode,
  ) async {
    await replaceReplyPurifyConfig(replyPurifyConfig.setCenterMode(mode));
  }

  static Future<void> setReplyKeywordPattern(String pattern) async {
    final value = pattern.trim();
    final regexp = RegExp(value, caseSensitive: false);
    replyRegExp = regexp;
    enableFilter = value.isNotEmpty;
    await GStorage.setting.put(SettingBoxKey.banWordForReply, value);
  }

  static Map<int, int> mentionSummaryForUser(int mid) =>
      _aiMentionTracker.mentionCountsForAuthor(mid);

  static ReplyDensityAssessment assessReplyDensity(ReplyInfo reply) {
    final content = reply.content;
    final mentionedMids = content.atNameToMid.values.map(
      (mid) => mid.toInt(),
    );
    return ReplyDensityDetector.assess(
      message: content.message,
      atNameToMid: content.atNameToMid.map(
        (name, mid) => MapEntry(name, mid.toInt()),
      ),
      structuredEmotes: content.emotes.keys,
      hasPictures: content.pictures.isNotEmpty,
      nickname: reply.member.name,
      repeatedMentionCount: _aiMentionTracker.repeatedMentionCount(
        authorMid: reply.mid.toInt(),
        mentionedMids: mentionedMids,
      ),
      config: ReplyDensityConfig(foldPureMentions: blockAtOnlyReply),
    );
  }

  static ReplyAiAssessment assessAiReply(ReplyInfo reply) =>
      assessReplyDensity(reply).aiAssessment;

  static void _observeAiReply(ReplyInfo reply) {
    _aiMentionTracker.observe(
      oid: reply.oid.toInt(),
      replyId: reply.id.toInt(),
      authorMid: reply.mid.toInt(),
      mentionedMids: reply.content.atNameToMid.values.map((mid) => mid.toInt()),
    );
    for (final child in reply.replies) {
      _observeAiReply(child);
    }
  }

  static void _observeAiReplies(Iterable<ReplyInfo> replies) {
    for (final reply in replies) {
      _observeAiReply(reply);
    }
  }

  static bool shouldFoldAiReply(
    ReplyInfo reply, [
    ReplyAiAssessment? assessment,
  ]) {
    final config = replyPurifyConfig;
    final mid = reply.mid.toInt();
    return config.aiFilterLevel != ReplyAiFilterLevel.off &&
        mid != Accounts.main.mid &&
        !config.trustsAiUser(mid) &&
        (assessment ?? assessAiReply(reply)).matches(config.aiFilterLevel);
  }

  static bool shouldFoldDensityReply(
    ReplyInfo reply, [
    ReplyDensityAssessment? assessment,
  ]) {
    return reply.mid.toInt() != Accounts.main.mid &&
        (assessment ?? assessReplyDensity(reply)).shouldFold;
  }

  // static Future replyInfo({required int rpid}) {
  //   return _request(
  //     GrpcUrl.replyInfo,
  //     ReplyInfoReq(rpid: Int64(rpid)),
  //     ReplyInfoReply.fromBuffer,
  //     onSuccess: (response) => response.reply,
  //   );
  // }

  static bool _hasGoods(Url url) =>
      url.hasExtra() &&
      (url.extra.goodsCmControl == Int64.ONE ||
          url.extra.hasGoodsItemId() ||
          url.extra.hasGoodsPrefetchedCache());

  // ref BiliRoamingX
  @pragma('vm:prefer-inline')
  static bool _needRemoveGoodGrpc(ReplyInfo reply) {
    return (reply.content.urls.isNotEmpty &&
            reply.content.urls.values.any(_hasGoods)) ||
        reply.content.message.contains(Constants.goodsUrlPrefix);
  }

  static bool _blockReplyAtCount(ReplyInfo reply) {
    return blockReplyAtCount != null &&
        reply.content.atNameToMid.length >= blockReplyAtCount!;
  }

  static bool needRemoveGrpc(ReplyInfo reply) {
    final mid = reply.mid.toInt();
    return replyPurifyConfig.contains(mid) ||
        GlobalData().blackMids.contains(mid) ||
        _blockReplyAtCount(reply) ||
        (antiGoodsReply && _needRemoveGoodGrpc(reply)) ||
        (enableFilter && replyRegExp.hasMatch(reply.content.message));
  }

  static Future<LoadingState<MainListReply>> mainList({
    required int type,
    required int oid,
    Int64? rpid,
    required Mode mode,
    required String? offset,
    required Int64? cursorNext,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.mainList,
      MainListReq(
        oid: Int64(oid),
        type: Int64(type),
        rpid: rpid,
        // cursor: CursorReq(
        //   mode: mode,
        //   next: cursorNext,
        // ),
        mode: mode,
        pagination: offset == null ? null : FeedPagination(offset: offset),
      ),
      MainListReply.fromBuffer,
    );
    if (res case Success(:final response)) {
      if (response.hasUpTop()) {
        _observeAiReply(response.upTop);
      }
      _observeAiReplies(response.replies);

      // keyword filter
      if (response.hasUpTop() && needRemoveGrpc(response.upTop)) {
        response.clearUpTop();
      }

      if (response.replies.isNotEmpty) {
        response.replies.removeWhere((item) {
          final hasMatch = needRemoveGrpc(item);
          if (!hasMatch && item.replies.isNotEmpty) {
            item.replies.removeWhere(needRemoveGrpc);
          }
          return hasMatch;
        });
      }
    }
    return res;
  }

  static Future<LoadingState<DetailListReply>> detailList({
    required int type,
    required int oid,
    required int root,
    required int rpid,
    required Mode mode,
    required String? offset,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.detailList,
      DetailListReq(
        oid: Int64(oid),
        type: Int64(type),
        root: Int64(root),
        rpid: Int64(rpid),
        scene: DetailListScene.REPLY,
        mode: mode,
        pagination: offset == null ? null : FeedPagination(offset: offset),
      ),
      DetailListReply.fromBuffer,
    );
    if (res.dataOrNull case final response?) {
      _observeAiReplies(response.root.replies);
      response.root.replies.removeWhere(needRemoveGrpc);
    }
    return res;
  }

  static Future<LoadingState<FoldListResp>> foldList({
    required int type,
    required int oid,
    required FeedPagination pagination,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.foldList,
      FoldListReq(
        oid: Int64(oid),
        type: Int64(type),
        pagination: pagination,
      ),
      FoldListResp.fromBuffer,
    );
    if (res.dataOrNull case final response?) {
      _observeAiReplies(response.replies);
      response.replies.removeWhere((item) {
        final hasMatch = needRemoveGrpc(item);
        if (!hasMatch && item.replies.isNotEmpty) {
          item.replies.removeWhere(needRemoveGrpc);
        }
        return hasMatch;
      });
    }
    return res;
  }

  static Future<LoadingState<DialogListReply>> dialogList({
    required int type,
    required int oid,
    required int root,
    required int dialog,
    required String? offset,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.dialogList,
      DialogListReq(
        oid: Int64(oid),
        type: Int64(type),
        root: Int64(root),
        dialog: Int64(dialog),
        pagination: offset == null ? null : FeedPagination(offset: offset),
      ),
      DialogListReply.fromBuffer,
    );
    if (res.dataOrNull case final response?) {
      _observeAiReplies(response.replies);
      response.replies.removeWhere(needRemoveGrpc);
    }
    return res;
  }

  static Future<LoadingState<SearchItemReply>> searchItem({
    required int page,
    required SearchItemType itemType,
    required int oid,
    required int type,
    String? keyword,
  }) {
    return GrpcReq.request(
      GrpcUrl.searchItem,
      SearchItemReq(
        cursor: SearchItemCursorReq(next: Int64(page), itemType: itemType),
        oid: Int64(oid),
        type: Int64(type),
        keyword: keyword,
      ),
      SearchItemReply.fromBuffer,
    );
  }

  static Future<LoadingState<TranslateReplyResp>> translateReply({
    required Int64 type,
    required Int64 oid,
    required Int64 rpid,
  }) {
    return GrpcReq.request(
      GrpcUrl.translateReply,
      TranslateReplyReq(type: type, oid: oid, rpids: [rpid]),
      TranslateReplyResp.fromBuffer,
    );
  }
}
