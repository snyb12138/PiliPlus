import 'package:material_ui/material_ui.dart';

/// Returns a literal keyword only after explicit confirmation. Saving the
/// keyword belongs to the caller, so cancellation never changes any rules.
Future<String?> showDanmakuKeywordDialog(
  BuildContext context, {
  required String content,
}) => showDialog<String>(
  context: context,
  builder: (_) => DanmakuKeywordDialog(content: content),
);

class DanmakuKeywordDialog extends StatefulWidget {
  const DanmakuKeywordDialog({required this.content, super.key});

  final String content;

  @override
  State<DanmakuKeywordDialog> createState() => _DanmakuKeywordDialogState();
}

class _DanmakuKeywordDialogState extends State<DanmakuKeywordDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.content.trim())
      ..addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  void _keepSelection() {
    final value = _controller.value;
    if (!value.selection.isValid || value.selection.isCollapsed) return;
    final keyword = value.selection.textInside(value.text).trim();
    _controller.value = TextEditingValue(
      text: keyword,
      selection: TextSelection.collapsed(offset: keyword.length),
    );
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selection = _controller.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed;
    final keyword = _controller.text.trim();
    return AlertDialog(
      title: const Text('提取弹幕关键词'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('删去不需要的文字，或选中文字后点击“仅保留选中”。'),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('danmaku-keyword-input'),
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '屏蔽关键词'),
            ),
            TextButton.icon(
              onPressed: hasSelection ? _keepSelection : null,
              icon: const Icon(Icons.content_cut),
              label: const Text('仅保留选中'),
            ),
            const SizedBox(height: 8),
            const Text(
              '确定后加入全局“绝对屏蔽”：隐藏所有包含该关键词的弹幕。'
              '标点按普通文字匹配，不作为正则表达式。',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: keyword.isEmpty
              ? null
              : () => Navigator.pop(context, keyword),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
