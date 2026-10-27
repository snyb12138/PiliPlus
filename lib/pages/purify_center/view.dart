import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/models/user/reply_ai_filter.dart';
import 'package:PiliPlus/utils/recommend_filter.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class PurifyCenterPage extends StatefulWidget {
  const PurifyCenterPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<PurifyCenterPage> createState() => _PurifyCenterPageState();
}

class _PurifyCenterPageState extends State<PurifyCenterPage> {
  Future<void> _open(String route) async {
    await Get.toNamed(route);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final danmaku = Pref.danmakuAssistantConfig;
    final ruleCount = danmaku.absoluteRules.length + danmaku.gentleRules.length;
    final formatCount = [
      danmaku.blockDateStamps,
      danmaku.blockTimeStamps,
      danmaku.blockPeopleCounts,
      danmaku.blockShortCheckIns,
    ].where((enabled) => enabled).length;
    final replyCount = ReplyGrpc.replyPurifyConfig.mutedUsers.length;
    final aiFilterLevel = ReplyGrpc.replyPurifyConfig.aiFilterLevel;
    final videoPurify = RecommendFilter.videoPurifyConfig;
    final padding = MediaQuery.viewPaddingOf(context);

    return SimpleScaffold(
      appBar: widget.showAppBar
          ? AppBar(title: const Text('PiliPlus 净化中心'))
          : null,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          12,
          widget.showAppBar ? 12 : 0,
          12,
          padding.bottom + 100,
        ),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('净化增强版', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    '把评论、弹幕与视频降噪规则集中在一处。所有匹配均在本机完成，不上传内容或屏蔽列表。',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  onTap: () => _open('/replyPurify'),
                  leading: const Icon(Icons.comments_disabled_outlined),
                  title: const Text('评论净化助手'),
                  subtitle: Text(
                    '$replyCount 个仅评论区屏蔽账号；'
                    'AI 评论检测${aiFilterLevel == ReplyAiFilterLevel.off ? '未启用' : '已启用·${aiFilterLevel.label}'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
                const Divider(height: 1),
                ListTile(
                  onTap: () => _open('/danmakuAssistant'),
                  leading: const Icon(Icons.subtitles_off_outlined),
                  title: const Text('弹幕屏蔽助手'),
                  subtitle: Text('$ruleCount 条文字规则，已启用 $formatCount 项格式识别'),
                  trailing: const Icon(Icons.chevron_right),
                ),
                const Divider(height: 1),
                ListTile(
                  onTap: () => _open('/videoPurify'),
                  leading: const Icon(Icons.video_library_outlined),
                  title: const Text('视频关键词屏蔽'),
                  subtitle: Text(
                    videoPurify.enabled
                        ? '已启用标题关键词过滤${videoPurify.applyToRelatedVideos ? '，包含相关视频' : ''}'
                        : '未启用；按标题过滤推荐、热门与排行视频',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.tune_outlined),
              title: Text('基础过滤仍然保留'),
              subtitle: Text(
                '评论关键词、带货评论、@ 数量和传统弹幕关键词/正则/UID 规则仍可在原设置与播放器菜单中使用。',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
