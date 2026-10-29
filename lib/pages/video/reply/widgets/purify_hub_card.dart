import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/models/user/reply_ai_filter.dart';
import 'package:PiliPlus/models/user/reply_density_detector.dart';
import 'package:PiliPlus/models/user/reply_purify.dart';
import 'package:PiliPlus/utils/recommend_filter.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class ReplyPurifyHubCard extends StatefulWidget {
  const ReplyPurifyHubCard({
    super.key,
    required this.onChanged,
    required this.ignoredForVideoCount,
    required this.onRestoreIgnoredForVideo,
    required this.undoAction,
    required this.onUndoAction,
    required this.onPurifyAction,
  });

  final VoidCallback onChanged;
  final int ignoredForVideoCount;
  final VoidCallback onRestoreIgnoredForVideo;
  final ReplyPurifyUndoAction? undoAction;
  final Future<void> Function() onUndoAction;
  final Future<void> Function(ReplyPurifyUndoAction action) onPurifyAction;

  @override
  State<ReplyPurifyHubCard> createState() => _ReplyPurifyHubCardState();
}

class _ReplyPurifyHubCardState extends State<ReplyPurifyHubCard> {
  Future<void> _setMode(ReplyPurifyCenterMode mode) async {
    await ReplyGrpc.setPurifyCenterMode(mode);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  Future<void> _open(String route) async {
    await Get.toNamed(route);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  Future<void> _setPureMentionFold(bool value) async {
    ReplyGrpc.blockAtOnlyReply = value;
    await GStorage.setting.put(SettingBoxKey.blockAtOnlyReply, value);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  void _restoreReplyRegex() {
    if (!ReplyGrpc.restoreReplyRegexForSession()) return;
    setState(() {});
    widget.onChanged();
    SmartDialog.showToast('评论正则已在当前进程重新启用');
  }

  Future<void> _editKeywords() async {
    final previousPattern = ReplyGrpc.replyRegExp.pattern;
    final controller = TextEditingController(
      text: previousPattern,
    );
    final pattern = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('评论屏蔽关键词库'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '示例：关键词A|关键词B',
            helperText: '支持正则表达式，不区分大小写；留空表示关闭',
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          TextButton(
            onPressed: () => Get.back(result: controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || pattern == null) return;
    try {
      await ReplyGrpc.setReplyKeywordPattern(pattern);
      if (pattern.trim() != previousPattern) {
        await widget.onPurifyAction(
          ReplyPurifyUndoAction.keywordPattern(
            previousPattern: previousPattern,
          ),
        );
      }
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
      SmartDialog.showToast(
        pattern.trim().isEmpty ? '已关闭评论关键词过滤' : '评论关键词已保存',
      );
    } on FormatException catch (error) {
      SmartDialog.showToast('正则表达式无效：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ReplyGrpc.replyPurifyConfig;
    final danmaku = Pref.danmakuAssistantConfig;
    final danmakuCount =
        danmaku.absoluteRules.length + danmaku.gentleRules.length;
    final keywordEnabled = ReplyGrpc.replyRegExp.pattern.isNotEmpty;
    final videoKeywordEnabled = RecommendFilter.enableFilter;
    final summary =
        '${config.mutedUsers.length} 个屏蔽账号 · '
        '${config.markedUsers.length} 个标记 · '
        '关键词${keywordEnabled ? '已启用' : '未启用'}'
        '${widget.ignoredForVideoCount == 0 ? '' : ' · 本视频忽略 ${widget.ignoredForVideoCount} 条'}';

    if (config.centerMode == ReplyPurifyCenterMode.collapsed) {
      return Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: ListTile(
          onTap: () => _setMode(ReplyPurifyCenterMode.expanded),
          leading: const Icon(Icons.shield_outlined),
          title: const Text('屏蔽中心'),
          subtitle: Text(summary),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '展开',
                onPressed: () => _setMode(ReplyPurifyCenterMode.expanded),
                icon: const Icon(Icons.expand_more),
              ),
              IconButton(
                tooltip: '隐藏',
                onPressed: () => _setMode(ReplyPurifyCenterMode.hidden),
                icon: const Icon(Icons.visibility_off_outlined),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.shield_outlined),
              title: const Text('屏蔽中心'),
              subtitle: Text(summary),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '折叠',
                    onPressed: () =>
                        _setMode(ReplyPurifyCenterMode.collapsed),
                    icon: const Icon(Icons.expand_less),
                  ),
                  IconButton(
                    tooltip: '隐藏',
                    onPressed: () => _setMode(ReplyPurifyCenterMode.hidden),
                    icon: const Icon(Icons.visibility_off_outlined),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _open('/replyPurify'),
                  icon: const Icon(Icons.comments_disabled_outlined, size: 18),
                  label: Text(
                    '评论名单 ${config.mutedUsers.length}/${config.markedUsers.length}',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _open('/danmakuAssistant'),
                  icon: const Icon(Icons.subtitles_off_outlined, size: 18),
                  label: Text('弹幕规则 $danmakuCount'),
                ),
                OutlinedButton.icon(
                  onPressed: _editKeywords,
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: Text(keywordEnabled ? '编辑关键词' : '添加关键词'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _open('/videoPurify'),
                  icon: const Icon(Icons.video_library_outlined, size: 18),
                  label: Text(
                    videoKeywordEnabled ? '视频关键词·已启用' : '视频关键词',
                  ),
                ),
                FilterChip(
                  selected: ReplyGrpc.blockAtOnlyReply,
                  avatar: const Icon(Icons.alternate_email, size: 16),
                  label: const Text('纯 @ 折叠'),
                  onSelected: _setPureMentionFold,
                ),
                if (ReplyGrpc.replyRegexSessionDisabled)
                  ActionChip(
                    avatar: const Icon(Icons.warning_amber_outlined, size: 16),
                    label: const Text('慢正则已停用·恢复'),
                    onPressed: _restoreReplyRegex,
                  ),
                if (widget.ignoredForVideoCount > 0)
                  ActionChip(
                    avatar: const Icon(Icons.restore, size: 16),
                    label: Text(
                      '恢复本视频忽略 ${widget.ignoredForVideoCount}',
                    ),
                    onPressed: widget.onRestoreIgnoredForVideo,
                  ),
                if (widget.undoAction case final action?)
                  ActionChip(
                    avatar: const Icon(Icons.undo, size: 16),
                    label: Text('撤销：${action.label}'),
                    onPressed: () => widget.onUndoAction(),
                  ),
                if (config.aiFilterLevel != ReplyAiFilterLevel.off)
                  Chip(
                    avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
                    label: Text('AI 检测·${config.aiFilterLevel.label}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
