import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliPlus/models/user/danmaku_block.dart';

class RegexSafetyResult {
  const RegexSafetyResult._({required this.ok, this.pattern, this.reason});

  const RegexSafetyResult.valid(String pattern)
    : this._(ok: true, pattern: pattern);

  const RegexSafetyResult.invalid(String reason)
    : this._(ok: false, reason: reason);

  final bool ok;
  final String? pattern;
  final String? reason;
}

abstract final class PurifyRegexSafety {
  static const int maxPatternLength = 256;
  static const int maxInputLength = 512;
  static const int slowMatchMilliseconds = 8;

  static RegexSafetyResult validate(String rawPattern) {
    final pattern = rawPattern.trim();
    if (pattern.isEmpty) {
      return const RegexSafetyResult.invalid('规则为空');
    }
    if (pattern.length > maxPatternLength) {
      return const RegexSafetyResult.invalid('规则超过 256 个字符');
    }
    if (RegExp(r'\\(?:[1-9]|k<)').hasMatch(pattern)) {
      return const RegexSafetyResult.invalid('暂不允许反向引用');
    }
    if (RegExp(r'\(\?<([=!])').hasMatch(pattern)) {
      return const RegexSafetyResult.invalid('暂不允许后行断言');
    }
    if (RegExp(r'(?:\.\*|\.\+).*(?:\.\*|\.\+)').hasMatch(pattern)) {
      return const RegexSafetyResult.invalid('包含多个高风险通配重复结构');
    }
    if (RegExp(
      r'\((?:\\.|\[[^\]]*\]|[^()])*[+*](?:\\.|\[[^\]]*\]|[^()])*\)\s*(?:[+*]|\{\d*,?\d*\})',
    ).hasMatch(pattern)) {
      return const RegexSafetyResult.invalid('包含嵌套重复量词，可能导致灾难性回溯');
    }
    try {
      RegExp(pattern, caseSensitive: false);
      return RegexSafetyResult.valid(pattern);
    } on FormatException catch (error) {
      return RegexSafetyResult.invalid('无法编译：${error.message}');
    }
  }
}

class RuleFilter {
  static final _regExp = RegExp(r'^/(.*)/$');

  List<String> dmFilterString = [];
  List<RegExp> dmRegExp = [];
  Set<String> dmUid = {};

  final Map<String, String> rejectedRegexRules = <String, String>{};
  final Map<String, String> _sessionDisabledRegexRules = <String, String>{};

  int count = 0;

  RuleFilter(this.dmFilterString, List<RegExp> regex, this.dmUid, [int? count]) {
    for (final regexp in regex) {
      _addRegexPattern(regexp.pattern);
    }
    this.count =
        count ?? dmFilterString.length + dmRegExp.length + dmUid.length;
  }

  RuleFilter.fromRuleTypeEntries(List<List<SimpleRule>> rules) {
    dmFilterString = rules[0].map((e) => e.filter).toList();
    for (final rule in rules[1]) {
      _addRegexPattern(_regExp.matchAsPrefix(rule.filter)?.group(1) ?? rule.filter);
    }
    dmUid = rules[2].map((e) => e.filter).toSet();
    count = dmFilterString.length + dmRegExp.length + dmUid.length;
  }

  RuleFilter.empty();

  Map<String, String> get sessionDisabledRegexRules =>
      Map.unmodifiable(_sessionDisabledRegexRules);

  bool restoreSessionDisabledRegex() {
    if (_sessionDisabledRegexRules.isEmpty) return false;
    _sessionDisabledRegexRules.clear();
    return true;
  }

  void _addRegexPattern(String pattern) {
    final result = PurifyRegexSafety.validate(pattern);
    if (!result.ok) {
      rejectedRegexRules[pattern] = result.reason ?? '规则不安全';
      return;
    }
    final safePattern = result.pattern!;
    dmRegExp.add(RegExp(safePattern, caseSensitive: false));
  }

  bool remove(DanmakuElem elem) {
    if (dmUid.contains(elem.midHash) ||
        dmFilterString.any((i) => elem.content.contains(i))) {
      return true;
    }
    if (elem.content.length > PurifyRegexSafety.maxInputLength) {
      return false;
    }
    for (final regexp in dmRegExp) {
      final pattern = regexp.pattern;
      if (_sessionDisabledRegexRules.containsKey(pattern)) continue;
      final stopwatch = Stopwatch()..start();
      try {
        final hit = regexp.hasMatch(elem.content);
        stopwatch.stop();
        if (stopwatch.elapsedMilliseconds >
            PurifyRegexSafety.slowMatchMilliseconds) {
          _sessionDisabledRegexRules[pattern] =
              '单次匹配耗时 ${stopwatch.elapsedMilliseconds}ms';
        }
        if (hit) return true;
      } catch (error) {
        stopwatch.stop();
        _sessionDisabledRegexRules[pattern] = '运行失败：$error';
      }
    }
    return false;
  }
}
