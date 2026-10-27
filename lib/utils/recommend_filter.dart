import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/models/user/video_purify.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

abstract final class RecommendFilter {
  static int minDurationForRcmd = Pref.minDurationForRcmd;
  static int minPlayForRcmd = Pref.minPlayForRcmd;
  static int minLikeRatioForRecommend = Pref.minLikeRatioForRecommend;
  static bool exemptFilterForFollowed = Pref.exemptFilterForFollowed;
  static bool applyFilterToRelatedVideos = Pref.applyFilterToRelatedVideos;
  static RegExp rcmdRegExp = RegExp(
    Pref.banWordForRecommend,
    caseSensitive: false,
  );
  static bool enableFilter = rcmdRegExp.pattern.isNotEmpty;

  static VideoPurifyConfig get videoPurifyConfig => VideoPurifyConfig(
    keywordPattern: rcmdRegExp.pattern,
    applyToRelatedVideos: applyFilterToRelatedVideos,
    exemptFollowedUploaders: exemptFilterForFollowed,
  );

  static Future<void> applyVideoPurifyConfig(
    VideoPurifyConfig config,
  ) async {
    final regexp = RegExp(config.keywordPattern, caseSensitive: false);
    rcmdRegExp = regexp;
    enableFilter = regexp.pattern.isNotEmpty;
    applyFilterToRelatedVideos = config.applyToRelatedVideos;
    exemptFilterForFollowed = config.exemptFollowedUploaders;
    await Future.wait([
      GStorage.setting.put(
        SettingBoxKey.banWordForRecommend,
        config.keywordPattern,
      ),
      GStorage.setting.put(
        SettingBoxKey.applyFilterToRelatedVideos,
        config.applyToRelatedVideos,
      ),
      GStorage.setting.put(
        SettingBoxKey.exemptFilterForFollowed,
        config.exemptFollowedUploaders,
      ),
    ]);
  }

  // (web/app)rcmd
  static bool filterWithExempt(BaseVideoItemModel videoItem) {
    //由于相关视频中没有已关注标签，只能视为非关注视频
    if (videoItem.isFollowed && exemptFilterForFollowed) {
      return false;
    }
    return filterAll(videoItem);
  }

  /// hot/rank/[filterAll]
  static bool filterLikeRatio(int? like, int? view) {
    if (view != null) {
      return (view > -1 && view < minPlayForRcmd) ||
          (like != null &&
              like > -1 &&
              like * 100 < minLikeRatioForRecommend * view);
    }
    return false;
  }

  /// hot/rank/[filterAll]
  static bool filterTitle(String title) {
    return (enableFilter && rcmdRegExp.hasMatch(title));
  }

  /// [filterAll]
  static bool filterDuration(int duration) {
    return duration > 0 && duration < minDurationForRcmd;
  }

  /// related/[filterWithExempt]
  static bool filterAll(BaseVideoItemModel videoItem) {
    return filterDuration(videoItem.duration) ||
        filterLikeRatio(videoItem.stat.like, videoItem.stat.view) ||
        filterTitle(videoItem.title);
  }
}
