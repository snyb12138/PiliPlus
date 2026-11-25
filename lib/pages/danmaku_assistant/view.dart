import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/dialog/export_import.dart';
import 'package:PiliPlus/models/user/danmaku_assistant.dart';
import 'package:PiliPlus/models/user/danmaku_spam/learning_export.dart';
import 'package:PiliPlus/models/user/danmaku_spam/learning_sample.dart';
import 'package:PiliPlus/pages/danmaku_assistant/keyword_dialog.dart';
import 'package:PiliPlus/pages/danmaku_assistant/records.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class DanmakuAssistantPage extends StatefulWidget {
  const DanmakuAssistantPage({super.key});

  @override
  State<DanmakuAssistantPage> createState() => _DanmakuAssistantPageState();
}

class _DanmakuAssistantPageState extends State<DanmakuAssistantPage> {
  PlPlayerController? _playerController;
  late DanmakuAssistantConfig _storedConfig;
  DanmakuAssistantConfig get _config =>
      _playerController?.danmakuAssistantConfig ?? _storedConfig;

  @override
  void initState() {
    super.initState();
    final arguments = Get.arguments;
    if (arguments is PlPlayerController) {
      _playerController = arguments;
    }
    _storedConfig =
        _playerController?.danmakuAssistantConfig ??
        Pref.danmakuAssistantConfig;
  }

  void _save(DanmakuAssistantConfig config) {
    setState(() => _storedConfig = config);
    final playerController = _playerController;
    if (playerController != null) {
      playerController.updateDanmakuAssistantConfig(config);
    } else {
      GStorage.localCache.put(
        LocalCacheKey.danmakuAssistantConfig,
        config.toStorage(),
      );
    }
  }

  Future<void> _addRule({required bool absolute}) async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(absolute ? '添加绝对屏蔽规则' : '添加温和屏蔽规则'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(absolute ? '只要弹幕包含该文字就会被屏蔽。' : '仅当整条弹幕与该文字相等时屏蔽。'),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              decoration: const InputDecoration(hintText: '输入规则'),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: textController,
              builder: (context, value, _) {
                final rule = value.text.trim();
                final samples = _playerController?.danmakuAssistantSamples;
                final hitCount = rule.isEmpty || samples == null
                    ? 0
                    : samples.where((item) {
                        final content = item.content.trim();
                        return absolute
                            ? content.contains(rule)
                            : content == rule;
                      }).length;
                return Text(
                  samples == null
                      ? '从播放器打开时可预览当前视频命中数'
                      : '当前已加载弹幕预计命中 $hitCount 条',
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (!mounted || result == null) return;

    final rule = result.trim();
    if (rule.isEmpty) return;
    if (absolute && !await confirmBroadShortNumericRule(context, rule)) {
      return;
    }
    if (!mounted) return;
    final rules = List<String>.of(
      absolute ? _config.absoluteRules : _config.gentleRules,
    );
    if (rules.any((item) => item.trim() == rule)) return;
    rules.add(rule);
    _save(
      absolute
          ? _config.copyWith(absoluteRules: rules)
          : _config.copyWith(gentleRules: rules),
    );
  }

  void _addGentleRule(String content) {
    final rule = content.trim();
    if (rule.isEmpty) return;
    final rules = List<String>.of(_config.gentleRules);
    if (rules.any((item) => item.trim() == rule)) return;
    rules.add(rule);
    _save(
      _config.copyWith(
        gentleRules: rules,
        learningSamples: DanmakuLearningSample.collect(
          _config.learningSamples,
          DanmakuLearningSample(content: content, keyword: rule, mode: 'exact'),
        ),
      ),
    );
  }

  Future<void> _addWhitelist() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('手动添加白名单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '弹幕完整原文',
            helperText: '仅豁免自动检测；整条匹配，不覆盖手动屏蔽规则',
            helperMaxLines: 3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || text == null || text.trim().isEmpty) return;
    if (_config.noiseWhitelist.contains(text.trim())) return;
    _save(
      _config.copyWith(
        noiseWhitelist: [..._config.noiseWhitelist, text.trim()],
      ),
    );
  }

  Future<void> _exportLearningData() async {
    final samples = List<DanmakuLearningSample>.of(_config.learningSamples);
    final whitelist = List<String>.of(_config.noiseWhitelist);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导出弹幕学习资料？'),
        content: Text(
          '将导出 ${samples.length} 条手动屏蔽样本和 '
          '${whitelist.length} 条手动白名单。屏蔽样本包含原文、关键词、'
          '匹配方式和重复次数；不包含发送者、账号、CID 或视频链接。'
          '不会自动上传，也不会自动生成规则。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('导出 JSON'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    exportToLocalFile(
      localFileName: () => 'danmaku_learning_v2',
      onExport: () => Utils.jsonEncoder.convert(
        DanmakuLearningExport.build(
          samples: samples,
          whitelist: whitelist,
        ),
      ),
    );
  }

  Widget _learningAndWhitelist() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionTitle(
        '手动白名单',
        trailing: IconButton(
          tooltip: '添加完整弹幕',
          onPressed: _addWhitelist,
          icon: const Icon(Icons.add),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 8,
          children: [
            for (final entry in _config.noiseWhitelist)
              InputChip(
                label: Text(entry),
                onDeleted: () => _save(
                  _config.copyWith(
                    noiseWhitelist: List<String>.of(_config.noiseWhitelist)
                      ..remove(entry),
                  ),
                ),
              ),
            if (_config.noiseWhitelist.isEmpty) const Text('暂无白名单；只由您手动添加或放行。'),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed:
                _config.learningSamples.isEmpty &&
                    _config.noiseWhitelist.isEmpty
                ? null
                : _exportLearningData,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('导出手动屏蔽与白名单 JSON'),
          ),
        ),
      ),
      ExpansionTile(
        title: Text('待学习名单 ${_config.learningSamples.length} 条'),
        subtitle: const Text('仅收集手动屏蔽；去重并保留最近 1000 条，随配置备份。'),
        children: [
          for (final sample in _config.learningSamples.take(50))
            ListTile(
              title: Text(sample.content),
              subtitle: Text(
                '关键词：${sample.keyword} · '
                '${sample.mode == 'contains' ? '包含匹配' : '整条匹配'} · ${sample.count} 次',
              ),
              trailing: IconButton(
                tooltip: '删除学习样本（不删除屏蔽规则）',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _save(
                  _config.copyWith(
                    learningSamples: List<DanmakuLearningSample>.of(
                      _config.learningSamples,
                    )..remove(sample),
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );

  void _removeRule(DanmakuAssistantKind kind, String rule) {
    switch (kind) {
      case DanmakuAssistantKind.absolute:
        _save(
          _config.copyWith(
            absoluteRules: List<String>.of(_config.absoluteRules)..remove(rule),
          ),
        );
        return;
      case DanmakuAssistantKind.gentle:
        _save(
          _config.copyWith(
            gentleRules: List<String>.of(_config.gentleRules)..remove(rule),
          ),
        );
        return;
      default:
        return;
    }
  }

  String _formatProgress(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _sectionTitle(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _ruleSection({required bool absolute}) {
    final rules = absolute ? _config.absoluteRules : _config.gentleRules;
    final kind = absolute
        ? DanmakuAssistantKind.absolute
        : DanmakuAssistantKind.gentle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          absolute ? '绝对屏蔽（包含即拦截）' : '温和屏蔽（整条相等才拦截）',
          trailing: IconButton(
            tooltip: '添加规则',
            onPressed: () => _addRule(absolute: absolute),
            icon: const Icon(Icons.add),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: rules.isEmpty
              ? const Text('暂无规则')
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: rules
                      .map(
                        (rule) => InputChip(
                          label: Text(rule),
                          onDeleted: () => _removeRule(kind, rule),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _stats() {
    final playerController = _playerController!;
    final theme = Theme.of(context);
    final total = playerController.danmakuAssistantBlockedTotal;
    final counts = playerController.danmakuAssistantReasonCounts;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '当前视频已拦截 $total 条',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: playerController.clearDanmakuAssistantRecords,
                  child: const Text('清空统计'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DanmakuAssistantKind.values
                  .where((kind) => (counts[kind] ?? 0) > 0)
                  .map(
                    (kind) =>
                        Chip(label: Text('${kind.label} ${counts[kind]}')),
                  )
                  .toList(),
            ),
            if (total == 0)
              Text('播放或拖动视频后，这里会显示本地命中统计。', style: theme.textTheme.bodySmall),
            if (playerController.danmakuSpamAllowedKeys.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('本视频已放行', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: playerController.danmakuSpamAllowedKeys
                    .map(
                      (key) => InputChip(
                        label: Text(key),
                        onDeleted: () =>
                            playerController.revokeDanmakuSpamAllowance(key),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _switches() => Column(
    children: [
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('格式识别默认关闭'),
        subtitle: Text('建议先查看当前视频的命中预览，再按需启用。'),
      ),
      SwitchListTile(
        title: const Text('日期与日期打卡'),
        subtitle: const Text('例如：2025.8探访古迹、10月1日 1000人'),
        value: _config.blockDateStamps,
        onChanged: (value) => _save(_config.copyWith(blockDateStamps: value)),
      ),
      SwitchListTile(
        title: const Text('时间打卡'),
        subtitle: const Text('例如：12:00 1000人'),
        value: _config.blockTimeStamps,
        onChanged: (value) => _save(_config.copyWith(blockTimeStamps: value)),
      ),
      SwitchListTile(
        title: const Text('纯人数刷屏'),
        subtitle: const Text('例如：1000人；不会误伤完整语句中的人数'),
        value: _config.blockPeopleCounts,
        onChanged: (value) => _save(_config.copyWith(blockPeopleCounts: value)),
      ),
      SwitchListTile(
        title: const Text('短打卡/考古'),
        subtitle: const Text('例如：2026年前来考古'),
        value: _config.blockShortCheckIns,
        onChanged: (value) =>
            _save(_config.copyWith(blockShortCheckIns: value)),
      ),
      SwitchListTile(
        title: const Text('重复短句/符号刷屏（测试）'),
        subtitle: const Text('默认关闭；合并长串连续字符为 3 个显示，拦截周期短句及时间/人数模板刷屏'),
        value: _config.blockRepeatedSpam,
        onChanged: (value) => _save(_config.copyWith(blockRepeatedSpam: value)),
      ),
      SwitchListTile(
        title: const Text('激进乱码过滤（测试）'),
        subtitle: const Text(
          '默认关闭；含英文弹幕命中孤立出现、混杂标点或不在常用组合表任一条件即屏蔽。正常英文也可能被拦截，请通过记录手动放行。',
        ),
        value: _config.strictNoiseFilter,
        onChanged: (value) => _save(_config.copyWith(strictNoiseFilter: value)),
      ),
    ],
  );

  Widget _records({required bool blocked}) {
    final playerController = _playerController!;
    final source = blocked
        ? playerController.danmakuAssistantHits
        : playerController.danmakuAssistantSamples;
    final records = source.reversed.take(blocked ? 80 : 50).toList();
    if (records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text('暂无数据'),
      );
    }

    return Column(
      children: records.map((record) {
        final match = record.match;
        final removableMatch =
            blocked &&
                match != null &&
                match.rule != null &&
                (match.kind == DanmakuAssistantKind.absolute ||
                    match.kind == DanmakuAssistantKind.gentle)
            ? match
            : null;
        final alreadyGentle = _config.gentleRules.any(
          (rule) => rule.trim() == record.content.trim(),
        );
        final repeatedSpam =
            blocked && match?.kind == DanmakuAssistantKind.repeatedSpam;
        return ListTile(
          dense: true,
          leading: Text(_formatProgress(record.progress)),
          title: Text(
            record.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: blocked && match != null ? Text(match.reason) : null,
          trailing: blocked
              ? removableMatch != null
                    ? IconButton(
                        tooltip: '移除此规则',
                        onPressed: () => _removeRule(
                          removableMatch.kind,
                          removableMatch.rule!,
                        ),
                        icon: const Icon(Icons.remove_circle_outline),
                      )
                    : repeatedSpam
                    ? IconButton(
                        tooltip: '本视频放行此短句',
                        onPressed: () => playerController
                            .allowDanmakuSpamForCurrentVideo(record.content),
                        icon: const Icon(Icons.visibility_outlined),
                      )
                    : null
              : IconButton(
                  tooltip: alreadyGentle ? '已在温和屏蔽中' : '按整条内容屏蔽',
                  onPressed: alreadyGentle
                      ? null
                      : () => _addGentleRule(record.content),
                  icon: const Icon(Icons.add_circle_outline),
                ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content() => ListView(
      children: [
        if (_playerController != null) _stats(),
        _sectionTitle('格式识别'),
        _switches(),
        _ruleSection(absolute: true),
        _ruleSection(absolute: false),
        _learningAndWhitelist(),
        if (_playerController != null) ...[
          _sectionTitle('弹幕净化记录'),
          DanmakuPurifyRecords(controller: _playerController!),
          _sectionTitle('最近读取的弹幕（点击 + 快速温和屏蔽）'),
          _records(blocked: false),
        ] else
          const ListTile(
            leading: Icon(Icons.preview_outlined),
            title: Text('命中预览与统计'),
            subtitle: Text('播放视频后，从播放器的弹幕菜单进入即可查看。'),
          ),
        const SizedBox(height: 32),
      ],
    );

    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('弹幕净化'),
        actions: [
          IconButton(
            tooltip: '恢复默认规则',
            onPressed: () => _save(DanmakuAssistantConfig.defaults()),
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: _playerController == null
          ? content()
          : Obx(() {
              final _ = _playerController!.danmakuAssistantRevision.value;
              return content();
            }),
    );
  }
}
