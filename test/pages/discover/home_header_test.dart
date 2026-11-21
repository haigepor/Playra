import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_header.dart';
import 'package:kazumi/pages/discover/home_layout.dart';

Future<List<MediaCategory>> _categories() async => const [
  MediaCategory(id: 'jp', name: '日本动漫'),
  MediaCategory(id: 'cn', name: '国产动漫'),
  MediaCategory(id: 'theatre', name: '剧场'),
];

Widget _harness(HomeLayoutMetrics layout) {
  return MaterialApp(
    home: Scaffold(
      body: HomeTopBar(
        layout: layout,
        sourceLabel: 'CliCli',
        categories: _categories(),
        onSearch: () {},
        onCategorySelected: (_) {},
        onCalendar: () {},
        onHistory: () {},
      ),
    ),
  );
}

Future<void> _setPhoneViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('phone header shows brand, search action and categories', (
    tester,
  ) async {
    await _setPhoneViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(HomeLayoutMetrics.phone));
    await tester.pump();

    expect(find.text('Playra'), findsOneWidget);

    expect(find.byTooltip('搜索'), findsOneWidget);
    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('日本动漫'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact phone header fits at 360x640', (tester) async {
    await _setPhoneViewport(tester, const Size(360, 640));
    await tester.pumpWidget(_harness(HomeLayoutMetrics.phoneCompact));
    await tester.pump();

    expect(find.text('Playra'), findsOneWidget);
    expect(find.byTooltip('搜索'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet portrait header fits at 853dp', (tester) async {
    await _setPhoneViewport(tester, const Size(853, 1280));
    await tester.pumpWidget(_harness(HomeLayoutMetrics.tabletPortrait));
    await tester.pump();

    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('搜索你感兴趣的内容…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet landscape header fits at 1280dp', (tester) async {
    await _setPhoneViewport(tester, const Size(1280, 853));
    await tester.pumpWidget(_harness(HomeLayoutMetrics.tabletLandscape));
    await tester.pump();

    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('搜索你感兴趣的内容…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
