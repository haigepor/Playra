import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_detail_page.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';

void main() {
  final raw = <String, dynamic>{
    'id': '9007199254740993',
    'title': '电影测试作品',
    'categoryName': '电影大全',
    'player': [
      {'playerCode': 'source_a', 'playerName': '线路甲'},
    ],
  };

  Future<MioMediaService> mount(
    WidgetTester tester,
    List<Map<String, dynamic>> calls, {
    double scale = 1,
    int count = 1,
    String Function(int)? label,
    Size size = const Size(320, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = MioMediaService(
      request: (operation, payload, cancel) async {
        calls.add({'operation': operation, ...payload});
        return {
          'data': switch (operation) {
            'detail' => {'video': raw},
            'episodes' => {
              'episodes': List.generate(
                count,
                (i) => {
                  'episodeNum': 12 + i * 2,
                  'displayName': label?.call(i) ?? '第${12 + i * 2}集',
                  'code': 'source_a',
                },
              ),
            },
            'play' => {'status': 'unavailable'},
            _ => {},
          },
        };
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: MioDetailPage(item: MioVideo.fromJson(raw), service: service),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  testWidgets(
    'light parent cannot change player sheet, borders or error contrast',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final service = await mount(tester, calls);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '第12集'),
      );
      expect(button.style!.side!.resolve({})!.color, const Color(0xff30384a));
      expect(
        Theme.of(tester.element(find.text('电影测试作品'))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.text('全部 1集 ›'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.backgroundColor, const Color(0xff11141c));
      expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(400));
      expect(find.text('线路甲 · 共 1 集'), findsOneWidget);
      final closeIcon = tester.widget<Icon>(find.byIcon(Icons.close_rounded));
      expect(closeIcon.color, const Color(0xffa5afc5));
      await tester.tap(find.byTooltip('关闭选集'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('简介 ›'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
        const Color(0xff11141c),
      );
      await tester.tap(find.byTooltip('关闭简介'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第12集'));
      await tester.pumpAndSettle();
      final notice = tester.widget<Container>(
        find.byKey(const ValueKey('miomedia-playback-notice')),
      );
      expect(
        (notice.decoration! as BoxDecoration).color,
        const Color(0xff1b202c),
      );
      final message = tester.widget<Text>(find.text('暂时无法取得播放资源，可重试或切换线路。'));
      expect(message.style!.color, const Color(0xffedf0f8));
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      final playCalls = calls.where((r) => r['operation'] == 'play').toList();
      expect(playCalls.length, 2);
      expect(
        playCalls.every(
          (r) =>
              r['videoId'] == raw['id'] &&
              r['episodeNum'] == 12 &&
              r['code'] == 'source_a',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );

  testWidgets(
    'long episode labels occupy a full row and segment slides without changing IDs',
    (tester) async {
      const longLabel = '20260401回顾：春日一起出发的旅行特别篇与嘉宾幕后故事';
      final calls = <Map<String, dynamic>>[];
      final service = await mount(
        tester,
        calls,
        count: 79,
        label: (i) => i == 0 ? longLabel : '第${12 + i * 2}集',
      );
      await tester.ensureVisible(find.text(longLabel));
      expect(
        tester.getSize(find.widgetWithText(OutlinedButton, longLabel)).width,
        288,
      );
      expect(tester.widget<Text>(find.text(longLabel)).maxLines, 2);
      await tester.tap(find.text('全部 79集 ›'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(longLabel).last).maxLines, 2);
      final tabs = tester.widget<TabBar>(
        find.byKey(const ValueKey('mio-episode-segments')),
      );
      await tester.tap(find.text('112–168'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tabs.controller!.animation!.value, greaterThan(0));
      expect(tabs.controller!.animation!.value, lessThan(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第112集'));
      await tester.pumpAndSettle();
      expect(calls.last['episodeNum'], 112);
      expect(calls.last['code'], 'source_a');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );

  testWidgets(
    'three episode card sizes share the same rule inline and in the sheet',
    (tester) async {
      const labels = [
        '第1集',
        '第2集',
        '20260404上',
        '20260405下',
        '20260401回顾：春日一起出发的旅行特别篇与嘉宾幕后故事',
      ];
      final service = await mount(
        tester,
        [],
        count: labels.length,
        label: (i) => labels[i],
        size: const Size(390, 844),
      );
      final short = find.widgetWithText(OutlinedButton, labels[0]);
      final middle = find.widgetWithText(OutlinedButton, labels[2]);
      final full = find.widgetWithText(OutlinedButton, labels[4]);
      expect(tester.getSize(short).width, closeTo(114, .01));
      expect(tester.getSize(middle).width, 175);
      expect(tester.getSize(full).width, 358);
      expect(
        tester.getTopLeft(middle).dy,
        tester.getTopLeft(find.widgetWithText(OutlinedButton, labels[3])).dy,
      );
      expect(tester.widget<Text>(find.text(labels[4])).maxLines, 2);
      await tester.tap(find.text('全部 5集 ›'));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.widgetWithText(OutlinedButton, labels[0]).last)
            .width,
        closeTo(83.5, .01),
      );
      expect(
        tester
            .getSize(find.widgetWithText(OutlinedButton, labels[2]).last)
            .width,
        175,
      );
      expect(
        tester
            .getSize(find.widgetWithText(OutlinedButton, labels[4]).last)
            .width,
        358,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );

  testWidgets(
    'large text adapts episode columns and descending preserves real identity',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final service = await mount(tester, calls, scale: 2, count: 80);
      await tester.tap(find.text('全部 80集 ›'));
      await tester.pumpAndSettle();
      final first = find.widgetWithText(OutlinedButton, '第12集').last;
      final second = find.widgetWithText(OutlinedButton, '第14集').last;
      expect(tester.getSize(first).width, 140);
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
      await tester.tap(find.text('升序'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第170集'));
      await tester.pumpAndSettle();
      expect(calls.last['episodeNum'], 170);
      expect(calls.last['code'], 'source_a');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );
}
