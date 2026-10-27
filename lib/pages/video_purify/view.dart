import 'package:PiliPlus/common/widgets/dialog/export_import.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/models/user/video_purify.dart';
import 'package:PiliPlus/utils/recommend_filter.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class VideoPurifyPage extends StatefulWidget {
  const VideoPurifyPage({super.key});

  @override
  State<VideoPurifyPage> createState() => _VideoPurifyPageState();
}

class _VideoPurifyPageState extends State<VideoPurifyPage> {
  VideoPurifyConfig get _config => RecommendFilter.videoPurifyConfig;

  Future<void> _apply(VideoPurifyConfig config) async {
    await RecommendFilter.applyVideoPurifyConfig(config);
    if (mounted) setState(() {});
  }

  Future<void> _editKeywords() async {
    final controller = TextEditingController(text: _config.keywordPattern);
    final pattern = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('视频标题屏蔽关键词'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '关键词A|关键词B',
            helperText: '使用 | 分隔多个关键词；支持正则表达式，不区分大小写；留空关闭',
            helperMaxLines: 3,
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          TextButton(
            onPressed: () => Get.back(result: controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || pattern == null) return;

    final value = pattern.trim();
    try {
      await _apply(_config.copyWith(keywordPattern: value));
      SmartDialog.showToast(
        value.isEmpty ? '已关闭视频关键词屏蔽' : '视频关键词已保存',
      );
    } on FormatException catch (error) {
      SmartDialog.showToast('正则表达式无效：$error');
    }
  }

  void _showImportExport() {
    showImportExportDialog<Map<String, dynamic>>(
      context,
      title: '视频净化配置',
      localFileName: () => 'video_purify',
      onExport: () => Utils.jsonEncoder.convert(_config.toStorage()),
      onImport: (json) => _apply(VideoPurifyConfig.fromStorage(json)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final padding = MediaQuery.viewPaddingOf(context);
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('视频关键词屏蔽'),
        actions: [
          IconButton(
            tooltip: '导入/导出',
            onPressed: _showImportExport,
            icon: const Icon(Icons.swap_vert),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: padding.bottom + 32),
        children: [
          const ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('仅在本机按标题过滤'),
            subtitle: Text('不会上传标题或关键词；规则为空时不屏蔽任何视频。'),
          ),
          const Divider(height: 1),
          ListTile(
            onTap: _editKeywords,
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('视频标题关键词库'),
            subtitle: Text(
              config.enabled ? config.keywordPattern : '未启用，点击添加关键词',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.edit_outlined),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.explore_outlined),
            title: const Text('同时过滤相关视频'),
            subtitle: const Text(
              '在视频详情页应用标题关键词；也会沿用推荐设置中的时长、播放量和点赞率过滤',
            ),
            value: config.applyToRelatedVideos,
            onChanged: (value) =>
                _apply(config.copyWith(applyToRelatedVideos: value)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.favorite_border_outlined),
            title: const Text('豁免已关注 UP 主'),
            subtitle: const Text(
              '推荐流中已关注账号发布的视频不按关键词屏蔽；相关视频无法识别关注状态',
            ),
            value: config.exemptFollowedUploaders,
            onChanged: (value) =>
                _apply(config.copyWith(exemptFollowedUploaders: value)),
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('当前作用范围'),
            subtitle: Text(
              '首页推荐、热门与排行；开启上方开关后也包括视频详情页的相关视频。搜索结果暂不处理。',
            ),
          ),
        ],
      ),
    );
  }
}
