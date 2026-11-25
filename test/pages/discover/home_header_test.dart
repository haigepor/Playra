import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/discover/home_header.dart';
import 'package:kazumi/pages/discover/home_layout.dart';

Widget _harness(
  HomeLayoutMetrics layout, {
  VoidCallback? onSearch,
  VoidCallback? onHistory,
  ValueChanged<int>? onChannelSelected,
  double textScale = 1,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: HomeTopBar(
        layout: layout,
        sourceLabel: 'CliCli',
        onSearch: onSearch ?? () {},
        onChannelSelected: onChannelSelected,
        onCalendar: () {},
        onHistory: onHistory ?? () {},
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
  for (final layout in [
    HomeLayoutMetrics.phone,
    HomeLayoutMetrics.tabletPortrait,
  ]) {
    testWidgets(
      '${layout.isPhone ? 'phone' : 'tablet'} search and history invoke callbacks',
      (tester) async {
        await _setPhoneViewport(
          tester,
          layout.isPhone ? const Size(390, 844) : const Size(853, 1280),
        );
        var searches = 0;
        var history = 0;
        await tester.pumpWidget(
          _harness(
            layout,
            onSearch: () => searches++,
            onHistory: () => history++,
          ),
        );
        await tester.pump();

        await tester.tap(
          layout.isPhone ? find.byTooltip('搜索') : find.text('搜索你感兴趣的内容…'),
        );
        await tester.tap(find.byTooltip('历史记录'));
        expect(searches, 1);
        expect(history, 1);
      },
    );
  }

  testWidgets('channel bar shows 6 fixed tabs, full-width divider and segmented track', (
    tester,
  ) async {
    await _setPhoneViewport(tester, const Size(390, 844));
    int? selected;
    await tester.pumpWidget(
      _harness(
        HomeLayoutMetrics.phone,
        onChannelSelected: (index) => selected = index,
      ),
    );
    await tester.pump();

    for (final label in const ['推荐', '热门', '动漫', '电视剧', '电影', '综艺']) {
      expect(find.text(label), findsOneWidget);
    }

    final dividerRect = tester.getRect(find.byType(Divider));
    expect(dividerRect.left, 0);
    expect(dividerRect.width, 390);

    await tester.tap(find.text('动漫'));
    await tester.pumpAndSettle();
    expect(selected, 2);
  });

  testWidgets('recommendation exposes selected semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await _setPhoneViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(HomeLayoutMetrics.phone));
    await tester.pump();
    expect(
      tester.getSemantics(find.text('推荐')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  for (final scenario in [
    (HomeLayoutMetrics.phoneCompact, const Size(320, 640)),
    (HomeLayoutMetrics.tabletPortrait, const Size(853, 1280)),
    (HomeLayoutMetrics.tabletLandscape, const Size(1280, 853)),
  ]) {
    testWidgets('header fits ${scenario.$2.width}dp with large text', (
      tester,
    ) async {
      await _setPhoneViewport(tester, scenario.$2);
      await tester.pumpWidget(_harness(scenario.$1, textScale: 2));
      await tester.pump();
      expect(find.text('推荐'), findsOneWidget);
      expect(find.text('热门'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone header shows brand, search action and channels', (
    tester,
  ) async {
    await _setPhoneViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(HomeLayoutMetrics.phone));
    await tester.pump();

    expect(find.text('Playra'), findsOneWidget);
    expect(find.byTooltip('搜索'), findsOneWidget);
    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
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

  testWidgets('tablet constrained width uses compact search', (tester) async {
    await _setPhoneViewport(tester, const Size(550, 900));
    var searches = 0;
    await tester.pumpWidget(
      _harness(HomeLayoutMetrics.tabletPortrait, onSearch: () => searches++),
    );
    await tester.pump();
    expect(find.byTooltip('搜索'), findsOneWidget);
    expect(find.text('推荐'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索'));
    expect(searches, 1);
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
