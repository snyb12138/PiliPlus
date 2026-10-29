import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/dialog/export_import.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/models/user/reply_ai_filter.dart';
import 'package:PiliPlus/models/user/reply_purify.dart';
import 'package:PiliPlus/utils/config_archive.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class ReplyPurifyPage extends StatefulWidget {
  const ReplyPurifyPage({super.key});

  @override
  State<ReplyPurifyPage> createState() => _ReplyPurifyPageState();
}

class _ReplyPurifyPageState extends State<ReplyPurifyPage> {
  ReplyPurifyConfig get _config => ReplyGrpc.replyPurifyConfig;

  Future<void> _addUser() async {
    final midController = TextEditingController();
    final nameController = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加仅评论区屏蔽账号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: midController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'UID（必填）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '备注名称（可选）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          TextButton(
            onPressed: () =>
                Get.back(result: (midController.text, nameController.text)),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    midController.dispose();
    nameController.dispose();
    if (!mounted || result == null) return;

    final mid = int.tryParse(result.$1);
    if (mid == null || mid <= 0) {
      SmartDialog.showToast('请输入有效 UID');
      return;
    }
    final added = await ReplyGrpc.muteReplyUser(mid, name: result.$2);
    if (!mounted) return;
    if (added) {
      setState(() {});
      SmartDialog.showToast('已添加');
    } else {
      SmartDialog.showToast('该 UID 已存在');
    }
  }

  Future<void> _removeUser(ReplyPurifyUser user) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text('取消屏蔽 ${user.name.isEmpty ? user.mid : user.name}？'),
    );
    if (!confirmed) return;
    await ReplyGrpc.unmuteReplyUser(user.mid);
    if (mounted) setState(() {});
  }

  Future<void> _clear() async {
    if (_config.mutedUsers.isEmpty) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: const Text('清空评论净化账号？'),
      content: const Text('清空后，这些账号的评论会重新显示。'),
    );
    if (!confirmed) return;
    await ReplyGrpc.replaceReplyPurifyConfig(
      _config.copyWith(mutedUsers: const {}),
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleAiFilter(bool enabled) async {
    await ReplyGrpc.setAiReplyFilterLevel(
      enabled ? ReplyAiFilterLevel.balanced : ReplyAiFilterLevel.off,
    );
    if (mounted) setState(() {});
  }

  Future<void> _selectAiFilterLevel() async {
    final selected = await showDialog<ReplyAiFilterLevel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('疑似 AI 评论检测强度'),
        content: RadioGroup<ReplyAiFilterLevel>(
          groupValue: _config.aiFilterLevel,
          onChanged: (value) => Get.back(result: value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final level in const [
                ReplyAiFilterLevel.conservative,
                ReplyAiFilterLevel.balanced,
              ])
                RadioListTile<ReplyAiFilterLevel>(
                  value: level,
                  title: Text(level.label),
                  subtitle: Text(
                    level == ReplyAiFilterLevel.conservative
                        ? '明确模型自述，或高置信度异常 @ 组合'
                        : '必须先命中异常重复 @；文本和昵称只用于辅助加分',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    await ReplyGrpc.setAiReplyFilterLevel(selected);
    if (mounted) setState(() {});
  }

  Future<void> _removeTrustedUser(ReplyPurifyUser user) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text('取消信任 ${user.name.isEmpty ? user.mid : user.name}？'),
      content: const Text('取消后，该账号的评论会重新参与 AI 特征检测。'),
    );
    if (!confirmed) return;
    await ReplyGrpc.untrustAiReplyUser(user.mid);
    if (mounted) setState(() {});
  }

  Future<void> _removeMarkedUser(ReplyPurifyUser user) async {
    await ReplyGrpc.unmarkReplyUser(user.mid);
    if (mounted) setState(() {});
  }

  Future<void> _blockMarkedUser(ReplyPurifyUser user) async {
    final added = await ReplyGrpc.muteReplyUser(user.mid, name: user.name);
    if (!mounted) return;
    if (added) {
      setState(() {});
      SmartDialog.showToast('已加入评论屏蔽列表');
    } else {
      SmartDialog.showToast('该账号已在评论屏蔽列表中');
    }
  }

  String _mentionSummary(int mid) {
    final entries = ReplyGrpc.mentionSummaryForUser(mid).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return '当前会话尚未观察到 @ 行为';
    return entries
        .take(3)
        .map((entry) => '@UID ${entry.key} ×${entry.value}')
        .join('，');
  }

  void _showImportExport() {
    showImportExportDialog<Map<String, dynamic>>(
      context,
      title: '评论净化配置',
      localFileName: () => 'reply_purify',
      onExport: () =>
          Utils.jsonEncoder.convert(ConfigArchive.exportPurifyConfig()),
      onImport: (json) async {
        final root = PurifyConfigV4.sanitizeMap(json);
        final reply = PurifyConfigV4.replySection(root);
        if (reply['mutedUsers'] is! Iterable) {
          throw const FormatException('缺少 mutedUsers 列表');
        }
        await ConfigArchive.importPurifyConfig(root);
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = _config.mutedUsers.values.toList()
      ..sort((a, b) => a.mid.compareTo(b.mid));
    final trustedUsers = _config.trustedAiUsers.values.toList()
      ..sort((a, b) => a.mid.compareTo(b.mid));
    final markedUsers = _config.markedUsers.values.toList()
      ..sort((a, b) => a.mid.compareTo(b.mid));
    final aiFilterEnabled = _config.aiFilterLevel != ReplyAiFilterLevel.off;
    final padding = MediaQuery.viewPaddingOf(context);
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('评论净化助手'),
        actions: [
          IconButton(
            tooltip: '导入/导出',
            onPressed: _showImportExport,
            icon: const Icon(Icons.swap_vert),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: users.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: padding.bottom + 100),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: const Text('折叠疑似 AI 低质量评论'),
            subtitle: Text(
              aiFilterEnabled
                  ? '已启用·${_config.aiFilterLevel.label}模式；命中后仍可查看原文'
                  : '默认关闭；所有检测均在本机完成',
            ),
            value: aiFilterEnabled,
            onChanged: _toggleAiFilter,
          ),
          if (aiFilterEnabled)
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('检测强度'),
              subtitle: const Text('优先使用组合特征，不会仅因为评论较长就折叠'),
              trailing: Text(_config.aiFilterLevel.label),
              onTap: _selectAiFilterLevel,
            ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('检测结果可解释'),
            subtitle: Text('折叠卡片会显示命中原因；重复 @ 仅在当前运行会话内统计，昵称或单次 @ 不会单独触发。'),
          ),
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('仅过滤评论，不加入全局黑名单'),
            subtitle: Text('规则只保存在本机；不会上传评论内容，也不会影响该用户的视频和动态。'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.comments_disabled_outlined),
            title: Text('评论屏蔽账号（${users.length}）'),
            subtitle: const Text('可通过评论昵称旁的屏蔽按钮直接添加'),
          ),
          if (users.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Center(child: Text('暂无屏蔽账号')),
            )
          else
            ...users.map(
              (user) => ListTile(
                onTap: () => Get.toNamed('/member?mid=${user.mid}'),
                leading: const Icon(Icons.person_off_outlined),
                title: Text(user.name.isEmpty ? 'UID ${user.mid}' : user.name),
                subtitle: user.name.isEmpty ? null : Text('UID ${user.mid}'),
                trailing: IconButton(
                  tooltip: '取消屏蔽',
                  onPressed: () => _removeUser(user),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text('标记库（${markedUsers.length}）'),
            subtitle: const Text('按 UID 排序；@ 行为统计仅显示当前运行会话'),
          ),
          if (markedUsers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Center(child: Text('暂无标记账号')),
            )
          else
            ...markedUsers.map(
              (user) => ListTile(
                onTap: () => Get.toNamed('/member?mid=${user.mid}'),
                leading: const Icon(Icons.flag_outlined),
                title: Text(user.name.isEmpty ? 'UID ${user.mid}' : user.name),
                subtitle: Text(
                  user.name.isEmpty
                      ? _mentionSummary(user.mid)
                      : 'UID ${user.mid} · ${_mentionSummary(user.mid)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '加入评论屏蔽列表',
                      onPressed: () => _blockMarkedUser(user),
                      icon: const Icon(Icons.comments_disabled_outlined),
                    ),
                    IconButton(
                      tooltip: '取消标记',
                      onPressed: () => _removeMarkedUser(user),
                      icon: const Icon(Icons.flag_outlined),
                    ),
                  ],
                ),
              ),
            ),
          if (trustedUsers.isNotEmpty) ...[
            const Divider(height: 24),
            const ListTile(
              leading: Icon(Icons.verified_user_outlined),
              title: Text('AI 检测信任账号'),
              subtitle: Text('这些账号不参与疑似 AI 评论检测'),
            ),
            ...trustedUsers.map(
              (user) => ListTile(
                onTap: () => Get.toNamed('/member?mid=${user.mid}'),
                leading: const Icon(Icons.person_outline),
                title: Text(user.name.isEmpty ? 'UID ${user.mid}' : user.name),
                subtitle: user.name.isEmpty ? null : Text('UID ${user.mid}'),
                trailing: IconButton(
                  tooltip: '取消信任',
                  onPressed: () => _removeTrustedUser(user),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ),
            ),
          ],
        ],
      ),
      fab: Padding(
        padding: EdgeInsets.only(
          right: kFloatingActionButtonMargin + padding.right,
          bottom: kFloatingActionButtonMargin + padding.bottom,
        ),
        child: FloatingActionButton(
          tooltip: '添加 UID',
          onPressed: _addUser,
          child: const Icon(Icons.person_add_alt_1_outlined),
        ),
      ),
    );
  }
}
