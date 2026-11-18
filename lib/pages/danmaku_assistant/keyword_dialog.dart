import 'package:PiliPlus/models/user/danmaku_spam/noise_policy.dart';
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

Future<bool> confirmBroadShortNumericRule(
  BuildContext context,
  String keyword,
) async {
  if (!DanmakuNoisePolicy.isShortPureNumber(keyword)) return true;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('确认使用短数字包含匹配？'),
      content: Text(
        '“$keyword”只有一到两位数字。包含匹配会同时屏蔽所有含有该数字的弹幕，'
        '例如“$keyword分钟”和“1$keyword级”。\n\n'
        '激进过滤已能屏蔽整条纯数字弹幕；通常无需再创建这条规则。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('仍然添加'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

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
