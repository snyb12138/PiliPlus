import 'dart:collection';

import 'package:PiliPlus/models/user/jm_reading_list.dart';

typedef ReplyNumberCursor = ({String? rootId, String? offset, bool folded});

class ReplyNumberComment {
  const ReplyNumberComment({
    required this.id,
    required this.rootId,
    required this.message,
    this.hasReplies = false,
    this.replies = const [],
  });

  final String id;
  final String rootId;
  final String message;
  final bool hasReplies;
  final List<ReplyNumberComment> replies;
}

class ReplyNumberPage {
  const ReplyNumberPage(this.comments, {this.nextOffset, this.foldOffset});

  final List<ReplyNumberComment> comments;
  final String? nextOffset;
  final String? foldOffset;
}

/// Independent of the live comment list. Each step requests only one page.
class ReplyNumberScan {
  ReplyNumberScan({String? startRootId}) {
    _enqueue(rootId: null);
    if (startRootId != null) _enqueue(rootId: startRootId);
  }

  final _pending = Queue<ReplyNumberCursor>();
  final _scheduled = <ReplyNumberCursor>{};
  final _seen = <String>{};
  final candidates = <({ReplyNumberComment comment, String number})>[];
  int get scanned => _seen.length;
  bool get hasMore => _pending.isNotEmpty;
  int skippedPages = 0;

  void skipPage() {
    _pending.removeFirst();
    skippedPages++;
  }

  void _enqueue({
    required String? rootId,
    String? offset,
    bool folded = false,
  }) {
    final cursor = (rootId: rootId, offset: offset, folded: folded);
    if (_scheduled.add(cursor)) _pending.addLast(cursor);
  }

  void _visit(ReplyNumberComment comment) {
    if (_seen.add(comment.id)) {
      final number = JmReadingList.assembleSearchCandidate(comment.message);
      if (number != null) candidates.add((comment: comment, number: number));
    }
    if (comment.id == comment.rootId &&
        (comment.hasReplies || comment.replies.isNotEmpty)) {
      _enqueue(rootId: comment.id);
    }
    for (final reply in comment.replies) {
      _visit(reply);
    }
  }

  Future<void> step(
    Future<ReplyNumberPage> Function(ReplyNumberCursor) load,
  ) async {
    final cursor = _pending.first;
    final page = await load(cursor);
    _pending.removeFirst();
    for (final comment in page.comments) {
      _visit(comment);
    }
    if (page.nextOffset case final offset? when offset.isNotEmpty) {
      _enqueue(rootId: cursor.rootId, offset: offset, folded: cursor.folded);
    }
    if (page.foldOffset case final offset?) {
      _enqueue(rootId: cursor.rootId, offset: offset, folded: true);
    }
  }
}
