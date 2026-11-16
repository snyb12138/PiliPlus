import 'package:material_ui/material_ui.dart';

class PurifyRecordSection extends StatelessWidget {
  const PurifyRecordSection({
    required this.commentCount,
    required this.danmakuCount,
    required this.showDanmakuRecords,
    required this.expanded,
    required this.onShowComments,
    required this.onShowDanmaku,
    required this.onToggleExpanded,
    required this.child,
    super.key,
  });

  final int commentCount;
  final int danmakuCount;
  final bool showDanmakuRecords;
  final bool expanded;
  final VoidCallback onShowComments;
  final VoidCallback onShowDanmaku;
  final VoidCallback onToggleExpanded;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.visibility_outlined),
          title: const Text('本视频净化记录'),
          trailing: TextButton.icon(
            key: const ValueKey('purify-records-toggle'),
            onPressed: onToggleExpanded,
            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            label: Text(expanded ? '收起' : '展开'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('purify-records-comments'),
                label: Text('评论净化 $commentCount'),
                selected: !showDanmakuRecords,
                onSelected: (_) => onShowComments(),
              ),
              ChoiceChip(
                key: const ValueKey('purify-records-danmaku'),
                label: Text('弹幕净化 $danmakuCount'),
                selected: showDanmakuRecords,
                onSelected: (_) => onShowDanmaku(),
              ),
            ],
          ),
        ),
        TickerMode(
          enabled: expanded,
          child: Offstage(
            offstage: !expanded,
            child: KeyedSubtree(
              key: const ValueKey('purify-records-content'),
              child: child,
            ),
          ),
        ),
      ],
    ),
  );
}
