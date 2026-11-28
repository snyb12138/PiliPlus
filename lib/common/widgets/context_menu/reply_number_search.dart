part of 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';

class _ReplyNumberSearchDialog extends StatefulWidget {
  const _ReplyNumberSearchDialog({
    required this.oid,
    required this.type,
    required this.startRootId,
  });

  final int oid;
  final int type;
  final String startRootId;

  @override
  State<_ReplyNumberSearchDialog> createState() =>
      _ReplyNumberSearchDialogState();
}

class _ReplyNumberSearchDialogState extends State<_ReplyNumberSearchDialog> {
  static const _pagesPerBatch = 30;
  late final _scan = ReplyNumberScan(
    startRootId: widget.startRootId == '0' ? null : widget.startRootId,
  );
  final _foldCursors = <(String?, String), FeedPagination>{};
  bool _busy = false;
  bool _failed = false;
  bool _pause = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  Iterable<ReplyNumberComment> _comments(
    Iterable<ReplyInfo> replies, {
    String? rootId,
  }) sync* {
    for (final reply in replies) {
      if (reply.id <= Int64.ZERO) continue;
      final id = reply.id.toString();
      final root =
          rootId ?? (reply.root > Int64.ZERO ? reply.root.toString() : id);
      yield ReplyNumberComment(
        id: id,
        rootId: root,
        message: reply.content.message,
        hasReplies: reply.count > Int64.ZERO,
        replies: _comments(reply.replies, rootId: root).toList(),
      );
    }
  }

  String? _rememberFold(String? rootId, Iterable<MixedCard> cards) {
    for (final card in cards) {
      if (card.type == .FOLD && card.fold.hasFoldPagination()) {
        final pagination = card.fold.foldPagination;
        _foldCursors[(rootId, pagination.offset)] = pagination;
        return pagination.offset;
      }
    }
    return null;
  }

  Future<ReplyNumberPage> _load(ReplyNumberCursor cursor) async {
    final (:rootId, :offset, :folded) = cursor;
    if (folded) {
      final res = await ReplyGrpc.foldList(
        type: widget.type,
        oid: widget.oid,
        pagination:
            _foldCursors[(rootId, offset)] ?? FeedPagination(offset: offset),
        scanOnly: true,
      );
      final page = res.data;
      return ReplyNumberPage(
        _comments(page.replies, rootId: rootId).toList(),
        nextOffset: page.paginationReply.nextOffset,
      );
    }
    if (rootId != null) {
      final res = await ReplyGrpc.detailList(
        type: widget.type,
        oid: widget.oid,
        root: int.parse(rootId),
        rpid: 0,
        mode: Mode.MAIN_LIST_HOT,
        offset: offset,
        scanOnly: true,
      );
      final page = res.data;
      return ReplyNumberPage(
        [
          if (page.root.id > Int64.ZERO)
            ..._comments([page.root], rootId: rootId)
          else
            ..._comments(page.root.replies, rootId: rootId),
        ],
        nextOffset: page.cursor.isEnd ? null : page.paginationReply.nextOffset,
        foldOffset: _rememberFold(rootId, page.mixedCards),
      );
    }
    final res = await ReplyGrpc.mainList(
      type: widget.type,
      oid: widget.oid,
      mode: Mode.MAIN_LIST_TIME,
      offset: offset,
      scanOnly: true,
    );
    final page = res.data;
    return ReplyNumberPage(
      _comments([if (page.hasUpTop()) page.upTop, ...page.replies]).toList(),
      nextOffset: page.cursor.isEnd ? null : page.paginationReply.nextOffset,
      foldOffset: _rememberFold(null, page.mixedCards),
    );
  }

  Future<void> _run() async {
    if (_busy || !_scan.hasMore) return;
    setState(() {
      _busy = true;
      _pause = false;
      _failed = false;
    });
    try {
      for (var i = 0; i < _pagesPerBatch && _scan.hasMore; i++) {
        if (!mounted || _pause) break;
        if (i > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (!mounted || _pause) break;
        }
        await _scan.step(_load);
        if (mounted) setState(() {});
      }
    } catch (_) {
      _failed = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _review(ReplyNumberComment comment, String number) {
    if (_busy) setState(() => _pause = true);
    showDialog<void>(
      context: context,
      builder: (_) => _JmNumberDialog(
        original: comment.message,
        initialIds: [number],
        source: widget.type == 1
            ? JmCommentSource(
                aid: widget.oid.toString(),
                rootId: comment.rootId,
                replyId: comment.id,
                excerpt: String.fromCharCodes(comment.message.runes.take(240)),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('评论编号候选'),
    content: SizedBox(
      width: 430,
      height: 390,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('已检查 ${_scan.scanned} 条 · ${_scan.candidates.length} 条候选'),
          Text(
            _busy
                ? (_pause ? '停止在当前页…' : '正在分页检查主楼与楼中楼…')
                : _failed
                ? '当前页加载失败。可重试，或跳过后继续。'
                : _scan.hasMore
                ? '还有未检查的评论，可继续搜索。'
                : _scan.skippedPages > 0
                ? '已检查可加载的评论，跳过 ${_scan.skippedPages} 页。'
                : '已检查接口返回的全部评论。',
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Expanded(
            child: _scan.candidates.isEmpty
                ? const Center(child: Text('暂无 5 位及以上的数字候选'))
                : ListView.builder(
                    itemCount: _scan.candidates.length,
                    itemBuilder: (_, index) {
                      final (:comment, :number) = _scan.candidates[index];
                      return ListTile(
                        title: Text(number),
                        subtitle: Text(
                          '${comment.id == comment.rootId ? '主楼' : '楼中楼'} · ${comment.message}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _review(comment, number),
                        trailing: IconButton(
                          tooltip: '复制候选',
                          onPressed: () => Utils.copyText(number),
                          icon: const Icon(Icons.copy_outlined),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      if (_failed)
        TextButton(
          onPressed: () {
            setState(() {
              _scan.skipPage();
              _failed = false;
            });
            _run();
          },
          child: const Text('跳过此页'),
        ),
      if (_busy)
        TextButton(
          onPressed: _pause ? null : () => setState(() => _pause = true),
          child: const Text('暂停'),
        )
      else if (_scan.hasMore)
        FilledButton(
          onPressed: _run,
          child: Text(_failed ? '重试' : '继续搜索'),
        ),
    ],
  );
}
