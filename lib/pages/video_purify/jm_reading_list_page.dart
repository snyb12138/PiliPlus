import 'package:PiliPlus/models/user/jm_reading_list.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/jm_reading_list_store.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

class JmReadingListTile extends StatelessWidget {
  const JmReadingListTile({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: JmReadingListStore.revision,
    builder: (context, _, _) {
      final count = JmReadingListStore.entries.length;
      return ListTile(
        leading: const Icon(Icons.bookmark_border),
        title: const Text('待阅读名单'),
        subtitle: Text('已确认 $count 个编号'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const _JmReadingListPage()),
        ),
        trailing: IconButton(
          tooltip: '导出到 JM Lite',
          icon: const Icon(Icons.file_download_outlined),
          onPressed: count == 0 ? null : JmReadingListStore.export,
        ),
      );
    },
  );
}

class _JmReadingListPage extends StatelessWidget {
  const _JmReadingListPage();

  Future<void> _remove(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除 $id？'),
        content: const Text('将从本机名单移除编号及其来源，不影响已导出的文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await JmReadingListStore.remove(id);
    } catch (_) {
      if (context.mounted) SmartDialog.showToast('移除失败，请重试');
    }
  }

  Future<void> _openSource(JmCommentSource source) async {
    final opened = await PiliScheme.routePush(source.link, selfHandle: true);
    if (!opened) SmartDialog.showToast('无法打开评论，可查看本地摘录');
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: JmReadingListStore.revision,
    builder: (context, _, _) {
      final entries = JmReadingListStore.entries.reversed.toList();
      return Scaffold(
        appBar: AppBar(
          title: const Text('待阅读名单'),
          actions: [
            IconButton(
              tooltip: '导出到 JM Lite',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: entries.isEmpty ? null : JmReadingListStore.export,
            ),
          ],
        ),
        body: entries.isEmpty
            ? const Center(child: Text('在视频评论的「自由复制」中选中文字并提取编号'))
            : ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return ExpansionTile(
                    key: PageStorageKey(entry.id),
                    title: Text(entry.id),
                    subtitle: Text('${entry.sources.length} 条评论来源'),
                    children: [
                      for (final source in entry.sources)
                        ListTile(
                          title: Text(
                            source.videoTitle?.isNotEmpty == true
                                ? source.videoTitle!
                                : '视频 av${source.aid}',
                          ),
                          subtitle: Text(
                            '${source.excerpt}\n评论 ID：${source.replyId}',
                          ),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => _openSource(source),
                        ),
                      TextButton.icon(
                        onPressed: () => _remove(context, entry.id),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('移除编号'),
                      ),
                    ],
                  );
                },
              ),
      );
    },
  );
}
