part of 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';

void showReplyCopyDialog(
  BuildContext context,
  String message,
  Map<String, Emote> emotes, {
  String? videoAid,
  required String rootReplyId,
  required String replyId,
  String? videoTitle,
}) {
  bool showEmote = false;
  String? selection;

  void extract(BuildContext context, String? text) {
    if (showEmote || text == null || text.trim().isEmpty) {
      SmartDialog.showToast('请先长按原文，选中含编号的文字');
      return;
    }
    final ids = JmReadingList.extractSelectionIds(text);
    if (ids.isEmpty) {
      SmartDialog.showToast('选区内没有可确认的 5–8 位编号');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => _JmNumberDialog(
        original: message,
        initialIds: ids,
        source: videoAid == null
            ? null
            : JmCommentSource(
                aid: videoAid,
                rootId: rootReplyId,
                replyId: replyId,
                excerpt: String.fromCharCodes(text.trim().runes.take(240)),
                videoTitle: videoTitle,
              ),
      ),
    );
  }

  showDialog(
    context: context,
    builder: (context) => Dialog(
      constraints: const BoxConstraints.tightFor(width: 380),
      child: Padding(
        padding: const .symmetric(horizontal: 20, vertical: 16),
        child: SelectionArea(
          onSelectionChanged: (content) => selection = content?.plainText,
          contextMenuBuilder: (_, state) {
            final buttonItems = state.contextMenuButtonItems;
            if (emotes.isNotEmpty) {
              buttonItems.insertOrAdd(
                3,
                ContextMenuButtonItem(
                  label: showEmote ? '文本' : '表情',
                  onPressed: () {
                    state.hideAndClear();
                    selection = null;
                    showEmote = !showEmote;
                    (context as Element).markNeedsBuild();
                  },
                ),
              );
            }
            state.addLaunchMenuIfNeeded(buttonItems, index: 4);
            final selectedText = state.selectedText;
            if (state.isUncollapsed && selectedText != null) {
              if (!showEmote &&
                  JmReadingList.extractSelectionIds(selectedText).isNotEmpty) {
                buttonItems.add(
                  ContextMenuButtonItem(
                    label: '提取编号',
                    onPressed: () {
                      state.hideAndClear();
                      extract(context, selectedText);
                    },
                  ),
                );
              }
              buttonItems.add(
                ContextMenuButtonItem(
                  onPressed: () {
                    String text = RegExp.escape(selectedText);
                    if (ReplyGrpc.enableFilter) text = '|$text';

                    showConfirmDialog(
                      context: context,
                      title: const Text('是否确认评论过滤的变更：'),
                      content: Text.rich(
                        TextSpan(
                          text: ReplyGrpc.replyRegExp.pattern,
                          children: [
                            TextSpan(
                              text: text,
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: .bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      onConfirm: () {
                        final filter = ReplyGrpc.replyRegExp.pattern + text;
                        ReplyGrpc.replyRegExp = RegExp(
                          filter,
                          caseSensitive: true,
                        );
                        ReplyGrpc.enableFilter = true;
                        GStorage.setting.put(
                          SettingBoxKey.banWordForReply,
                          filter,
                        );
                        SmartDialog.showToast('已保存');
                      },
                    );
                  },
                  label: '加入过滤',
                ),
              );
            }
            return AdaptiveTextSelectionToolbar.buttonItems(
              buttonItems: buttonItems,
              anchors: state.contextMenuAnchors,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Text.rich(
                    showEmote
                        ? TextSpan(
                            children: emotes.entries.mapIndexed((i, e) {
                              final emote = e.value;
                              final size = emote.size.toInt() * 25.0;
                              return TextSpan(
                                children: [
                                  if (i != 0) const TextSpan(text: '\n\n'),
                                  WidgetSpan(
                                    child: NetworkImgLayer(
                                      src: emote.url,
                                      type: .emote,
                                      width: size,
                                      height: size,
                                    ),
                                  ),
                                  TextSpan(text: '\n${e.key}\n${emote.url}'),
                                ],
                              );
                            }).toList(),
                          )
                        : TextSpan(text: message),
                    style: const TextStyle(fontSize: 15, height: 1.7),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SelectionContainer.disabled(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => extract(context, selection),
                    child: const Text('提取编号'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _JmNumberDialog extends StatefulWidget {
  const _JmNumberDialog({
    required this.original,
    required this.initialIds,
    required this.source,
  });

  final String original;
  final List<String> initialIds;
  final JmCommentSource? source;

  @override
  State<_JmNumberDialog> createState() => _JmNumberDialogState();
}

class _JmNumberDialogState extends State<_JmNumberDialog> {
  late final _input = TextEditingController(text: widget.initialIds.join('\n'));
  late List<String> _ids = JmReadingList.extractIds(_input.text);
  bool _saving = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() => _saving = true);
    try {
      final accepted = await JmReadingListStore.add(_ids, widget.source!);
      if (!mounted) return;
      if (accepted) {
        Navigator.pop(context);
        SmartDialog.showToast('待阅读名单已保存');
      } else {
        SmartDialog.showToast('待阅读名单最多保存 5000 个编号，请先手动删除旧条目');
      }
    } catch (_) {
      if (mounted) SmartDialog.showToast('保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('确认提取的编号'),
    scrollable: true,
    content: SizedBox(
      width: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('评论原文'),
          const SizedBox(height: 4),
          SelectableText(widget.original),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            enabled: !_saving,
            minLines: 1,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '编号（可编辑）',
              helperText: '每组 5–8 位，多个编号用换行分隔',
            ),
            onChanged: (value) =>
                setState(() => _ids = JmReadingList.extractIds(value)),
          ),
          if (widget.source == null) const Text('仅视频评论支持保存来源并加入待阅读名单。'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: _saving || _ids.isEmpty
            ? null
            : () => Utils.copyText(_ids.join('\n'), toastText: '已复制编号'),
        child: const Text('复制编号'),
      ),
      if (widget.source != null)
        FilledButton(
          onPressed: _saving || _ids.isEmpty ? null : _add,
          child: const Text('加入待阅读名单'),
        ),
    ],
  );
}
