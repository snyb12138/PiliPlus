import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/models/user/reply_ai_filter.dart';
import 'package:PiliPlus/models/user/reply_density_detector.dart';
import 'package:PiliPlus/pages/video/reply/widgets/purify_hub_card.dart';
import 'package:PiliPlus/utils/recommend_filter.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class PurifyCenterPage extends StatefulWidget {
  const PurifyCenterPage({
    super.key,
    this.showAppBar = true,
    this.videoSession,
    this.onReplyReload,
  });

  final bool showAppBar;
  final ReplyPurifyVideoSession? videoSession;
  final Future<void> Function()? onReplyReload;

  @override
  State<PurifyCenterPage> createState() => _PurifyCenterPageState();
}

class _PurifyCenterPageState extends State<PurifyCenterPage> {
  Future<void> _open(String route) async {
    await Get.toNamed(route);
    if (mounted) setState(() {});
  }

  void _restoreDanmakuRegex() {
    if (Pref.danmakuFilterRule.restoreSessionDisabledRegex() && mounted) {
      setState(() {});
    }
  }

  Future<void> _reloadReplies() async {
    await widget.onReplyReload?.call();
  }

  Future<void> _recordPurifyAction(ReplyPurifyUndoAction action) async {
    widget.videoSession?.rememberUndo(action);
    if (action.requiresReplyReload) await _reloadReplies();
  }

  Future<void> _undoPurifyAction() async {
    final session = widget.videoSession;
    final action = session?.undoAction;
    if (session == null || action == null) return;
    switch (action.type) {
      case ReplyPurifyUndoActionType.muteUser:
        await ReplyGrpc.unmuteReplyUser(action.mid);
        break;
      case ReplyPurifyUndoActionType.markUser:
        await ReplyGrpc.unmarkReplyUser(action.mid);
        break;
      case ReplyPurifyUndoActionType.unmarkUser:
        await ReplyGrpc.markReplyUser(action.mid, name: action.name);
        break;
      case ReplyPurifyUndoActionType.keywordPattern:
        await ReplyGrpc.setReplyKeywordPattern(action.previousKeywordPattern);
        break;
    }
    session.clearUndo(action);
    if (action.requiresReplyReload) await _reloadReplies();
  }

  Future<void> _restoreIgnoredForVideo() async {
    if (widget.videoSession?.clearIgnored() ?? false) {
      await _reloadReplies();
    }
  }

  Future<void> _showForVideo(ReplyPurifyPreviewEntry entry) async {
    if (widget.videoSession?.ignore(entry.replyId) ?? false) {
      await _reloadReplies();
    }
  }

  Widget _buildVideoPreview(ReplyPurifyVideoSession session) {
    final entries = session.previewEntries;
    final groups = <int, List<ReplyPurifyPreviewEntry>>{};
    for (final entry in entries) {
      groups.putIfAbsent(entry.threadId, () => []).add(entry);
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('本视频净化记录'),
            subtitle: Text(
              '已折叠 ${session.foldedCount} 条 · 已屏蔽 ${session.blockedCount} 条',
            ),
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('当前已加载评论中没有折叠或屏蔽内容。'),
            )
          else
            ...groups.values.map((items) {
              final first = items.first;
              return ExpansionTile(
                leading: Icon(
                  items.any(
                    (item) =>
                        item.action == ReplyPurifyPreviewAction.blocked,
                  )
                      ? Icons.comments_disabled_outlined
                      : Icons.auto_awesome_outlined,
                ),
                title: Text('@${first.name.isEmpty ? first.mid : first.name}'),
                subtitle: Text(
                  '${items.length} 条 · ${items.expand((item) => item.reasons).toSet().join('、')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                children: items.map((entry) {
                  final actionLabel =
                      entry.action == ReplyPurifyPreviewAction.folded
                      ? '已折叠'
                      : '已屏蔽';
                  return ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(32, 4, 12, 8),
                    title: Text(
                      entry.message.isEmpty ? '（无文字内容）' : entry.message,
                    ),
                    subtitle: Text('$actionLabel · ${entry.reasons.join('、')}'),
                    trailing: TextButton(
                      onPressed: () => _showForVideo(entry),
                      child: const Text('本视频显示'),
                    ),
                  );
                }).toList(),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.videoSession;
    if (session != null) {
      return ListenableBuilder(
        listenable: session,
        builder: (context, _) => _buildPage(context, session),
      );
    }
    return _buildPage(context, null);
  }

  Widget _buildPage(
    BuildContext context,
    ReplyPurifyVideoSession? session,
  ) {
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
    final traditionalDanmaku = Pref.danmakuFilterRule;
    final slowRegexCount =
        traditionalDanmaku.sessionDisabledRegexRules.length;
    final rejectedRegexCount = traditionalDanmaku.rejectedRegexRules.length;
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
          if (session != null) ...[
            _buildVideoPreview(session),
            const SizedBox(height: 8),
            ReplyPurifyHubCard(
              embedded: true,
              ignoredForVideoCount: session.ignoredCount,
              onRestoreIgnoredForVideo: _restoreIgnoredForVideo,
              undoAction: session.undoAction,
              onUndoAction: _undoPurifyAction,
              onPurifyAction: _recordPurifyAction,
              onChanged: () {
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 8),
          ],
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
          if (slowRegexCount > 0 || rejectedRegexCount > 0)
            Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: const Text('正则安全状态'),
                subtitle: Text(
                  '本进程停用慢规则 $slowRegexCount 条；'
                  '拒绝高风险规则 $rejectedRegexCount 条',
                ),
                trailing: slowRegexCount == 0
                    ? null
                    : TextButton(
                        onPressed: _restoreDanmakuRegex,
                        child: const Text('重新启用'),
                      ),
              ),
            ),
          if (slowRegexCount > 0 || rejectedRegexCount > 0)
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
