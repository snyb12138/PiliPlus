enum ReplyAiFilterLevel {
  off,
  conservative,
  balanced;

  factory ReplyAiFilterLevel.fromStorage(dynamic raw) {
    if (raw is String) {
      return ReplyAiFilterLevel.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => ReplyAiFilterLevel.off,
      );
    }
    return ReplyAiFilterLevel.off;
  }

  String get label => switch (this) {
    ReplyAiFilterLevel.off => '关闭',
    ReplyAiFilterLevel.conservative => '谨慎',
    ReplyAiFilterLevel.balanced => '均衡',
  };

  int get threshold => switch (this) {
    ReplyAiFilterLevel.off => 1 << 30,
    ReplyAiFilterLevel.conservative => 8,
    ReplyAiFilterLevel.balanced => 6,
  };
}

enum ReplyAiSignal {
  modelDisclosure('模型或 AI 自述'),
  cannedOpening('模板化开头'),
  cannedClosing('模板化结尾'),
  structuredList('机械分点'),
  formalConnectors('过渡词密集'),
  contrastTemplate('固定对照句式'),
  causalChain('机械因果链'),
  verboseExplanation('长文解释模板');

  const ReplyAiSignal(this.label);

  final String label;
}

class ReplyAiAssessment {
  const ReplyAiAssessment({required this.score, required this.signals});

  static const none = ReplyAiAssessment(score: 0, signals: []);

  final int score;
  final List<ReplyAiSignal> signals;

  bool matches(ReplyAiFilterLevel level) => score >= level.threshold;

  String get summary => signals.take(3).map((signal) => signal.label).join('、');
}

abstract final class ReplyAiDetector {
  static final RegExp _modelDisclosure = RegExp(
    r'(?:作为.{0,8}(?:AI|人工智能|语言模型))|'
    r'(?:(?:DeepSeek|豆包|文心一言|通义千问).{0,12}(?:生成|回答|总结|模型))|'
    r'(?:(?:生成|回答).{0,12}(?:DeepSeek|AI))',
    caseSensitive: false,
  );
  static final RegExp _cannedOpening = RegExp(
    r'^(?:以下是|我来帮你|可以从以下|针对这个问题|关于这个问题)',
  );
  static final RegExp _cannedClosing = RegExp(
    r'(?:希望以上|综上所述|总的来说|总体而言|'
    r'如果你还有.{0,12}(?:问题|疑问)|以上就是.{0,16}(?:总结|分析))',
  );
  static final RegExp _listMarker = RegExp(
    r'(?:^|\n)\s*(?:\d{1,2}[.\u3001。)]|[-*•])\s*',
    multiLine: true,
  );
  static final List<RegExp> _formalConnectors = [
    RegExp(r'首先'),
    RegExp(r'其次'),
    RegExp(r'最后'),
    RegExp(r'此外'),
    RegExp(r'同时'),
    RegExp(r'从.{0,12}角度来看'),
    RegExp(r'(?:需要|值得)注意的是'),
    RegExp(r'换句话说'),
  ];
  static final RegExp _contrastTemplate = RegExp(
    r'(?:这|它|其)?并不是.{0,48}而是|'
    r'不是.{0,48}而是',
  );
  static final List<RegExp> _causalMarkers = [
    RegExp(r'只要.{0,32}(?:就会|就能|可以)'),
    RegExp(r'系统就会'),
    RegExp(r'然后.{0,24}(?:就会|就能|可以|把)'),
    RegExp(r'因此|从而|进而'),
    RegExp(r'这意味着'),
    RegExp(r'必要的时候|必要时'),
  ];
  static final RegExp _clausePunctuation = RegExp(r'[，。！？；,.!?;]');

  static ReplyAiAssessment assess(String rawMessage) {
    final message = rawMessage.trim();
    if (message.isEmpty) return ReplyAiAssessment.none;

    var score = 0;
    final signals = <ReplyAiSignal>[];

    void add(ReplyAiSignal signal, int points) {
      if (signals.contains(signal)) return;
      signals.add(signal);
      score += points;
    }

    if (_modelDisclosure.hasMatch(message)) {
      add(ReplyAiSignal.modelDisclosure, 8);
    }
    if (_cannedOpening.hasMatch(message)) {
      add(ReplyAiSignal.cannedOpening, 3);
    }
    if (_cannedClosing.hasMatch(message)) {
      add(ReplyAiSignal.cannedClosing, 3);
    }

    // Short conversational replies should not be classified only because they
    // contain an ordinary transition word.
    if (message.length < 40) {
      return ReplyAiAssessment(
        score: score,
        signals: List.unmodifiable(signals),
      );
    }

    if (_listMarker.allMatches(message).length >= 2) {
      add(ReplyAiSignal.structuredList, 3);
    }

    final connectorCount = _formalConnectors
        .where((pattern) => pattern.hasMatch(message))
        .length;
    if (connectorCount >= 3) {
      add(ReplyAiSignal.formalConnectors, 2);
    }

    if (_contrastTemplate.hasMatch(message)) {
      add(ReplyAiSignal.contrastTemplate, 2);
    }

    final causalCount = _causalMarkers
        .where((pattern) => pattern.hasMatch(message))
        .length;
    if (causalCount >= 2) {
      add(ReplyAiSignal.causalChain, 3);
    }

    final punctuationCount = _clausePunctuation.allMatches(message).length;
    if ((message.length >= 100 && punctuationCount >= 5) ||
        (message.length >= 180 && punctuationCount >= 3)) {
      add(ReplyAiSignal.verboseExplanation, 1);
    }

    return ReplyAiAssessment(score: score, signals: List.unmodifiable(signals));
  }
}
