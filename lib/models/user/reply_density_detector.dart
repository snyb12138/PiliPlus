import 'package:PiliPlus/models/user/reply_ai_filter.dart';
import 'package:characters/characters.dart';

enum ReplyDensityCandidateType {
  none,
  singlePureMention,
  multiplePureMentions,
  shortText,
  pureEmote,
  pureImage,
}

class ReplyDensityConfig {
  const ReplyDensityConfig({
    this.foldPureMentions = false,
    this.multipleMentionThreshold = 2,
    this.shortTextMaxCharacters = 4,
  }) : assert(multipleMentionThreshold >= 2),
       assert(shortTextMaxCharacters >= 1);

  final bool foldPureMentions;
  final int multipleMentionThreshold;
  final int shortTextMaxCharacters;
}

class ReplyDensityAssessment {
  const ReplyDensityAssessment({
    required this.candidateType,
    required this.mentionOccurrenceCount,
    required this.distinctMentionMidCount,
    required this.effectiveTextLength,
    required this.shouldFold,
    required this.pendingReview,
    required this.aiAssessment,
  });

  final ReplyDensityCandidateType candidateType;
  final int mentionOccurrenceCount;
  final int distinctMentionMidCount;
  final int effectiveTextLength;
  final bool shouldFold;
  final bool pendingReview;
  final ReplyAiAssessment aiAssessment;

  /// Automatic detection never writes a permanent blacklist entry.
  bool get shouldPermanentlyBlock => false;

  List<String> get reasonLabels {
    final labels = <String>[
      if (candidateType != ReplyDensityCandidateType.none) candidateType.name,
      ...aiAssessment.signals.map((signal) => signal.name),
    ];
    return List.unmodifiable(labels);
  }
}

abstract final class ReplyDensityDetector {
  static ReplyDensityAssessment assess({
    required String message,
    required Map<String, int> atNameToMid,
    Iterable<String> structuredEmotes = const [],
    bool hasPictures = false,
    String nickname = '',
    int repeatedMentionCount = 0,
    ReplyDensityConfig config = const ReplyDensityConfig(),
  }) {
    final emoteTokens = structuredEmotes
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toSet();

    var normalized = message;
    for (final token in emoteTokens) {
      normalized = normalized.replaceAll(token, ' ');
    }

    final mentionScan = _scanMentions(normalized, atNameToMid);
    final visibleClusters = mentionScan.remaining.characters
        .where((cluster) => !_isWhitespaceOrPunctuationCluster(cluster))
        .toList(growable: false);
    final effectiveClusters = visibleClusters
        .where((cluster) => !_looksLikeEmojiCluster(cluster))
        .toList(growable: false);

    final effectiveTextLength = effectiveClusters.length;
    final hasStructuredEmotes = emoteTokens.isNotEmpty;
    final unicodeEmojiOnly =
        visibleClusters.isNotEmpty &&
        visibleClusters.every(_looksLikeEmojiCluster);

    var candidateType = ReplyDensityCandidateType.none;

    if (effectiveTextLength == 0 &&
        hasPictures &&
        !hasStructuredEmotes &&
        visibleClusters.isEmpty) {
      candidateType = ReplyDensityCandidateType.pureImage;
    } else if (effectiveTextLength == 0 &&
        !hasPictures &&
        ((hasStructuredEmotes && visibleClusters.isEmpty) ||
            (!hasStructuredEmotes && unicodeEmojiOnly))) {
      candidateType = ReplyDensityCandidateType.pureEmote;
    } else if (!hasPictures &&
        !hasStructuredEmotes &&
        mentionScan.occurrenceCount > 0 &&
        visibleClusters.isEmpty) {
      candidateType =
          mentionScan.occurrenceCount >= config.multipleMentionThreshold
          ? ReplyDensityCandidateType.multiplePureMentions
          : ReplyDensityCandidateType.singlePureMention;
    } else if (effectiveTextLength > 0 &&
        effectiveTextLength <= config.shortTextMaxCharacters) {
      candidateType = ReplyDensityCandidateType.shortText;
    }

    final isPureMention =
        candidateType == ReplyDensityCandidateType.singlePureMention ||
        candidateType == ReplyDensityCandidateType.multiplePureMentions;
    final aiAssessment = ReplyAiDetector.assess(
      message,
      nickname: nickname,
      repeatedMentionCount: repeatedMentionCount,
    );

    return ReplyDensityAssessment(
      candidateType: candidateType,
      mentionOccurrenceCount: mentionScan.occurrenceCount,
      distinctMentionMidCount: mentionScan.distinctMids.length,
      effectiveTextLength: effectiveTextLength,
      shouldFold: isPureMention && config.foldPureMentions,
      pendingReview:
          candidateType == ReplyDensityCandidateType.multiplePureMentions ||
          candidateType == ReplyDensityCandidateType.shortText ||
          candidateType == ReplyDensityCandidateType.pureEmote ||
          candidateType == ReplyDensityCandidateType.pureImage,
      aiAssessment: aiAssessment,
    );
  }

  static _MentionScan _scanMentions(
    String message,
    Map<String, int> atNameToMid,
  ) {
    final names = atNameToMid.keys
        .where((name) => name.isNotEmpty)
        .toList(growable: false)
      ..sort((a, b) => b.length.compareTo(a.length));
    if (names.isEmpty || !message.contains('@')) {
      return _MentionScan(
        remaining: message,
        occurrenceCount: 0,
        distinctMids: const {},
      );
    }

    final remaining = StringBuffer();
    final distinctMids = <int>{};
    var occurrenceCount = 0;
    var index = 0;

    while (index < message.length) {
      String? matchedName;
      if (message.codeUnitAt(index) == 0x40) {
        for (final name in names) {
          final end = index + 1 + name.length;
          if (end <= message.length &&
              message.startsWith(name, index + 1) &&
              _isMentionBoundary(message, end)) {
            matchedName = name;
            break;
          }
        }
      }

      if (matchedName == null) {
        remaining.writeCharCode(message.codeUnitAt(index));
        index++;
        continue;
      }

      occurrenceCount++;
      final mid = atNameToMid[matchedName];
      if (mid != null && mid > 0) distinctMids.add(mid);
      remaining.write(' ');
      index += matchedName.length + 1;
    }

    return _MentionScan(
      remaining: remaining.toString(),
      occurrenceCount: occurrenceCount,
      distinctMids: Set.unmodifiable(distinctMids),
    );
  }

  static bool _isMentionBoundary(String message, int index) {
    if (index >= message.length) return true;
    final rune = _runeAt(message, index);
    return rune == 0x40 ||
        _isWhitespaceOrPunctuationRune(rune) ||
        _isEmojiRune(rune);
  }

  static int _runeAt(String value, int index) {
    final first = value.codeUnitAt(index);
    if (first >= 0xD800 && first <= 0xDBFF && index + 1 < value.length) {
      final second = value.codeUnitAt(index + 1);
      if (second >= 0xDC00 && second <= 0xDFFF) {
        return 0x10000 +
            ((first - 0xD800) << 10) +
            (second - 0xDC00);
      }
    }
    return first;
  }

  static bool _isWhitespaceOrPunctuationCluster(String cluster) {
    return cluster.runes.every(_isWhitespaceOrPunctuationRune);
  }

  static bool _isWhitespaceOrPunctuationRune(int rune) {
    if (rune <= 0x20 || rune == 0x7F || rune == 0xA0) return true;
    if ((rune >= 0x21 && rune <= 0x2F) ||
        (rune >= 0x3A && rune <= 0x40) ||
        (rune >= 0x5B && rune <= 0x60) ||
        (rune >= 0x7B && rune <= 0x7E)) {
      return true;
    }
    return (rune >= 0x2000 && rune <= 0x206F) ||
        (rune >= 0x2E00 && rune <= 0x2E7F) ||
        (rune >= 0x3000 && rune <= 0x303F) ||
        (rune >= 0xFE10 && rune <= 0xFE1F) ||
        (rune >= 0xFE30 && rune <= 0xFE4F) ||
        (rune >= 0xFF01 && rune <= 0xFF0F) ||
        (rune >= 0xFF1A && rune <= 0xFF20) ||
        (rune >= 0xFF3B && rune <= 0xFF40) ||
        (rune >= 0xFF5B && rune <= 0xFF65);
  }

  static bool _looksLikeEmojiCluster(String cluster) {
    return cluster.runes.any(_isEmojiRune);
  }

  static bool _isEmojiRune(int rune) {
    return (rune >= 0x1F000 && rune <= 0x1FAFF) ||
        (rune >= 0x2600 && rune <= 0x27BF) ||
        (rune >= 0x2300 && rune <= 0x23FF) ||
        (rune >= 0x1F1E6 && rune <= 0x1F1FF) ||
        (rune >= 0x1F3FB && rune <= 0x1F3FF) ||
        rune == 0x200D ||
        rune == 0x20E3 ||
        rune == 0xFE0F;
  }
}

class _MentionScan {
  const _MentionScan({
    required this.remaining,
    required this.occurrenceCount,
    required this.distinctMids,
  });

  final String remaining;
  final int occurrenceCount;
  final Set<int> distinctMids;
}
