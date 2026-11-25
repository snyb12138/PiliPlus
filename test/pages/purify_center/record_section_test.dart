import 'package:PiliPlus/pages/purify_center/record_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('collapsing hides only the record list and preserves counts', (
    tester,
  ) async {
    var expanded = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return PurifyRecordSection(
                commentCount: 3,
                danmakuCount: 34,
                showDanmakuRecords: true,
                expanded: expanded,
                onShowComments: () {},
                onShowDanmaku: () {},
                onToggleExpanded: () {
                  setState(() => expanded = !expanded);
                },
                child: const Text('已过滤名单内容'),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('评论净化 3'), findsOneWidget);
    expect(find.text('弹幕净化 34'), findsOneWidget);
    expect(find.text('已过滤名单内容'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('purify-records-toggle')));
    await tester.pump();
    expect(find.text('已过滤名单内容'), findsNothing);
    expect(find.text('评论净化 3'), findsOneWidget);
    expect(find.text('弹幕净化 34'), findsOneWidget);
    expect(find.text('展开'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('purify-records-toggle')));
    await tester.pump();
    expect(find.text('已过滤名单内容'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('record type can be changed while the list is collapsed', (
    tester,
  ) async {
    var showDanmaku = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PurifyRecordSection(
              commentCount: 2,
              danmakuCount: 5,
              showDanmakuRecords: showDanmaku,
              expanded: false,
              onShowComments: () => setState(() => showDanmaku = false),
              onShowDanmaku: () => setState(() => showDanmaku = true),
              onToggleExpanded: () {},
              child: Text(showDanmaku ? '弹幕名单' : '评论名单'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('purify-records-danmaku')));
    await tester.pump();
    final danmakuChip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('purify-records-danmaku')),
    );
    expect(danmakuChip.selected, isTrue);
    expect(find.text('弹幕名单'), findsNothing);
  });
}
