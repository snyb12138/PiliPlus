import 'package:PiliPlus/models/user/danmaku_assistant.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Shared by the video shield page and the danmaku settings page.
class DanmakuPurifyRecords extends StatelessWidget {
  const DanmakuPurifyRecords({required this.controller, super.key});

  final PlPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final records = controller.danmakuAssistantHits.reversed.take(200).toList();
    if (records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('当前已加载弹幕中暂无净化记录。'),
      );
    }
    return Column(
      children: [
        ListTile(
          title: Text('已屏蔽 ${controller.danmakuAssistantBlockedTotal} 条'),
          subtitle: const Text('展示最近 200 条原文；自动判断不写入永久黑名单。'),
        ),
        for (final record in records)
          ListTile(
            leading: Text(
              '${record.progress ~/ 60000}:'
              '${(record.progress ~/ 1000 % 60).toString().padLeft(2, '0')}',
            ),
            title: SelectableText(record.content),
            subtitle: Text(record.match?.reason ?? '已屏蔽'),
            trailing: PopupMenuButton<String>(
              tooltip: '放行操作',
              itemBuilder: (_) => [
                if (record.match?.rule != null)
                  const PopupMenuItem(value: 'remove', child: Text('移除此屏蔽规则…')),
                if (record.match?.kind == DanmakuAssistantKind.traditionalRule)
                  const PopupMenuItem(value: 'manage', child: Text('管理传统弹幕规则')),
                if (record.match?.kind != DanmakuAssistantKind.absolute &&
                    record.match?.kind != DanmakuAssistantKind.gentle &&
                    record.match?.kind != DanmakuAssistantKind.traditionalRule)
                  const PopupMenuItem(value: 'video', child: Text('本视频放行')),
                if (record.match?.kind != DanmakuAssistantKind.absolute &&
                    record.match?.kind != DanmakuAssistantKind.gentle &&
                    record.match?.kind != DanmakuAssistantKind.traditionalRule)
                  const PopupMenuItem(
                    value: 'whitelist',
                    child: Text('加入全局白名单…'),
                  ),
              ],
              onSelected: (action) async {
                if (action == 'manage') {
                  await Get.toNamed('/danmakuBlock', arguments: controller);
                  controller.reloadDanmakuFilters();
                  return;
                }
                if (action == 'video') {
                  controller.allowDanmakuSpamForCurrentVideo(record.content);
                  return;
                }
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text(action == 'remove' ? '移除此屏蔽规则？' : '加入全局白名单？'),
                    content: Text(
                      action == 'remove'
                          ? '规则：${record.match?.rule}\n移除后，所有视频中仅被此规则命中的弹幕将恢复显示。'
                          : '仅放行整条相同内容：\n${record.content}\n\n'
                                '白名单豁免自动检测，不覆盖您主动设置的屏蔽规则。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                if (action == 'remove') {
                  final config = controller.danmakuAssistantConfig;
                  controller.updateDanmakuAssistantConfig(
                    record.match?.kind == DanmakuAssistantKind.absolute
                        ? config.copyWith(
                            absoluteRules: List<String>.of(config.absoluteRules)
                              ..remove(record.match?.rule),
                          )
                        : config.copyWith(
                            gentleRules: List<String>.of(config.gentleRules)
                              ..remove(record.match?.rule),
                          ),
                  );
                } else {
                  controller.allowDanmakuGlobally(record.content);
                }
              },
            ),
          ),
      ],
    );
  }
}
