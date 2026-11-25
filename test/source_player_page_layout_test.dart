import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/player/source_player_page.dart';
import 'package:kazumi/pages/route_args.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/shell/shell_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;
  setUpAll(() async {
    data = await Directory.systemTemp.createTemp('playra-player-layout-');
    Hive.init(data.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await GStorage.close();
    await data.delete(recursive: true);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'landscape tablet shows detail beside episodes at scale $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 800);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final request = PlaybackRequest(
          sourceId: 'no-network',
          roadCode: 'main',
          episode: 999,
          detail: MediaDetail(
            key: const MediaKey(sourceId: 'no-network', mediaId: 'tablet'),
            title: '平板播放详情',
            description: '示例简介',
            roads: [
              MediaRoad(
                code: 'main',
                name: '主线路',
                episodes: [
                  MediaEpisode(number: 1, title: '真实标题'),
                  MediaEpisode(number: 2, title: '需要会员的剧集', vipOnly: true),
                ],
              ),
            ],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildShellTheme(Brightness.dark),
            home: SourcePlayerPage(request: request),
          ),
        );
        await tester.pump();
        expect(find.text('平板播放详情'), findsOneWidget);
        expect(find.text('选集'), findsOneWidget);
        expect(find.text('真实标题'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('选集')).dx,
          greaterThan(tester.getTopLeft(find.text('平板播放详情')).dx),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
    testWidgets('portrait playback page remains usable at text scale $scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final episodes = List.generate(
        12,
        (i) => MediaEpisode(
          number: i + 1,
          title: i == 0 ? '真正的第一集标题' : '第${i + 1}集',
          vipOnly: i == 0,
        ),
      );
      final request = PlaybackRequest(
        sourceId: 'no-network',
        roadCode: 'main',
        episode:
            999, // Deliberately missing: exercises the page without opening native media.
        detail: MediaDetail(
          key: const MediaKey(sourceId: 'no-network', mediaId: 'item'),
          title: '一部很长很长的作品标题用于检查播放页面的显示和省略',
          episodeStatus: '更新至 12 集',
          description: '这是用于检查播放器简介显示和展开操作的文本。' * 8,
          subtitle: '测试别名',
          score: 9.0,
          tags: const ['悬疑', '冒险'],
          roads: [MediaRoad(code: 'main', name: '主线路', episodes: episodes)],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildShellTheme(Brightness.dark),
          home: SourcePlayerPage(request: request),
        ),
      );
      await tester.pump();
      expect(find.text('播放失败'), findsOneWidget);
      expect(find.text('暂无可播放剧集'), findsOneWidget);
      expect(find.text('播放'), findsOneWidget);
      expect(find.text('简介与资料'), findsOneWidget);
      expect(find.text('选集'), findsOneWidget);
      expect(find.text('主线路'), findsOneWidget);
      final title = tester.widget<Text>(find.text(request.detail.title));
      expect(title.maxLines, isNull);
      await tester.scrollUntilVisible(
        find.text('真正的第一集标题'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('01'), findsOneWidget);
      expect(find.text('需要会员'), findsOneWidget);
      final inkWell = tester.widget<InkWell>(
        find.ancestor(
          of: find.text('真正的第一集标题'),
          matching: find.byType(InkWell),
        ),
      );
      expect(inkWell.onTap, isNull);
      // Switch to 简介与资料 tab and verify full description & metadata appear.
      await tester.tap(find.text('简介与资料'));
      await tester.pumpAndSettle();
      expect(find.text('剧情简介'), findsOneWidget);
      expect(find.text('悬疑'), findsOneWidget);
      expect(find.text('测试别名'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets(
    'portrait numeric episodes render compact 5-column grid and anchored all-episodes overlay',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final episodes = List.generate(
        30,
        (i) => MediaEpisode(
          number: i + 1,
          title: '第${(i + 1).toString().padLeft(4, '0')}集',
        ),
      );
      final request = PlaybackRequest(
        sourceId: 'no-network',
        roadCode: 'rrys',
        episode: 999,
        detail: MediaDetail(
          key: const MediaKey(sourceId: 'no-network', mediaId: 'jiumen'),
          title: '九门-电视剧',
          year: 2026,
          area: '内地',
          category: '影视天地',
          episodeStatus: '更新至 30 集',
          score: 9.0,
          subtitle: 'jm',
          description: '长沙风云再起。',
          tags: const ['国产剧', '悬疑'],
          roads: [
            MediaRoad(code: 'rrys', name: 'rrys', episodes: episodes),
            MediaRoad(code: 'hd2', name: '高清线路 2', episodes: episodes),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildShellTheme(Brightness.dark),
          home: SourcePlayerPage(request: request),
        ),
      );
      await tester.pumpAndSettle();

      // 5-column compact grid shows 01..10 directly without redundant 第0001集 text.
      expect(find.text('01'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('第0001集'), findsNothing);
      expect(find.text('rrys'), findsOneWidget);
      expect(find.text('高清线路 2'), findsOneWidget);
      expect(find.text('投屏'), findsOneWidget);
      expect(find.text('定时关闭'), findsOneWidget);
      expect(find.text('超分画质'), findsOneWidget);
      expect(find.text('外部播放'), findsOneWidget);

      // Open anchored all-episodes overlay below video.
      await tester.tap(find.text('全部 30 集'));
      await tester.pumpAndSettle();
      expect(find.text('全部选集 · 30 集'), findsOneWidget);
      expect(find.text('1–20'), findsOneWidget);
      expect(find.text('21–30'), findsOneWidget);
      await tester.tap(find.text('21–30'));
      await tester.pumpAndSettle();
      expect(find.text('30'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭全部选集'));
      await tester.pumpAndSettle();
      expect(find.text('全部选集 · 30 集'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
