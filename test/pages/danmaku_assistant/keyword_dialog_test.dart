import 'package:PiliPlus/models/user/danmaku_assistant.dart';
import 'package:PiliPlus/pages/danmaku_assistant/keyword_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _openDialog(
  WidgetTester tester, {
  required String content,
  required ValueChanged<String?> onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showDanmakuKeywordDialog(
                context,
                content: content,
              );
              onResult(result);
            },
            child: const Text('提取'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('提取'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('editing returns a trimmed keyword only after confirmation', (
    tester,
  ) async {
    String? saved;
    await _openDialog(
      tester,
      content: '我活到头了？竟然更新饥荒',
      onResult: (value) => saved = value,
    );
    expect(find.text('我活到头了？竟然更新饥荒'), findsOneWidget);
    expect(saved, isNull);
    await tester.enterText(find.byType(TextField), '  更新饥荒  ');
    expect(saved, isNull);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(saved, '更新饥荒');

    final config = DanmakuAssistantConfig.defaults().copyWith(
      absoluteRules: [saved!],
    );
    expect(config.match('终于更新饥荒了')?.kind, DanmakuAssistantKind.absolute);
    expect(config.match('终于更新其他游戏了'), isNull);
    expect(
      DanmakuAssistantConfig.fromStorage(config.toStorage()).absoluteRules,
      ['更新饥荒'],
    );
  });

  testWidgets('cancel does not return a keyword', (tester) async {
    String? saved;
    var completed = false;
    await _openDialog(
      tester,
      content: '测试弹幕',
      onResult: (value) {
        saved = value;
        completed = true;
      },
    );
    await tester.enterText(find.byType(TextField), '修改后');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(saved, isNull);
  });

  testWidgets('whitespace cannot be confirmed', (tester) async {
    await _openDialog(tester, content: '测试', onResult: (_) {});
    await tester.enterText(find.byType(TextField), '   ');
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('keeps the selected substring including unicode characters', (
    tester,
  ) async {
    String? saved;
    const source = '前缀😀关键词后缀';
    const selected = '😀关键词';
    await _openDialog(
      tester,
      content: source,
      onResult: (value) => saved = value,
    );
    final input = tester.widget<TextField>(find.byType(TextField));
    input.controller!.selection = TextSelection(
      baseOffset: source.indexOf(selected),
      extentOffset: source.indexOf(selected) + selected.length,
    );
    await tester.pump();
    await tester.tap(find.text('仅保留选中'));
    await tester.pump();
    expect(input.controller!.text, selected);
    expect(saved, isNull);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(saved, selected);
  });

  testWidgets(
    'punctuation is saved as literal text, not a regular expression',
    (tester) async {
      String? saved;
      const keyword = r'/.*[?]';
      await _openDialog(
        tester,
        content: keyword,
        onResult: (value) => saved = value,
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(saved, keyword);
      final config = DanmakuAssistantConfig.defaults().copyWith(
        absoluteRules: [saved!],
      );
      expect(config.match('前缀$keyword后缀'), isNotNull);
      expect(config.match('普通文字'), isNull);
    },
  );
}
