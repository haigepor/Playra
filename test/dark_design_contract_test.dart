import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/storage/favorite_storage.dart';
import 'package:kazumi/shell/playra_bottom_nav.dart';
import 'package:kazumi/shell/shell_theme.dart';
import 'package:kazumi/pages/player/player_transport_bar.dart';
import 'package:kazumi/presentation/widgets/playra_page_header.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/media_widgets.dart';

void main() {
  testWidgets('browse keeps two poster columns at 320dp and double text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: CustomScrollView(
              slivers: [
                MediaPosterGrid(
                  insets: const EdgeInsets.symmetric(horizontal: 16),
                  items: [
                    for (var i = 0; i < 3; i++)
                      MediaItem(
                        key: MediaKey(sourceId: 'test', mediaId: '$i'),
                        title: '作品$i',
                      ),
                  ],
                  onTap: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final first = tester.getTopLeft(find.bySemanticsLabel('查看 作品0'));
    final second = tester.getTopLeft(find.bySemanticsLabel('查看 作品1'));
    expect(second.dy, first.dy);
    expect(second.dx, greaterThan(first.dx));
    expect(tester.takeException(), isNull);
  });
  testWidgets('a single grid poster exposes its own tappable semantic bounds', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              MediaPosterGrid(
                phoneColumns: 2,
                items: const [
                  MediaItem(
                    key: MediaKey(sourceId: 'test', mediaId: '1'),
                    title: '作品',
                  ),
                ],
                onTap: (_) => opened = true,
              ),
            ],
          ),
        ),
      ),
    );
    final poster = find.bySemanticsLabel('查看 作品');
    await tester.tap(poster);
    expect(opened, isTrue);
    expect(tester.getSize(poster).width, lessThan(180));
    expect(tester.takeException(), isNull);
  });
  testWidgets('large root headers stay at the content gutter', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: Column(
              children: [PlayraPageHeader(title: '我的', largeTitle: true)],
            ),
          ),
        ),
      ),
    );
    expect(tester.getTopLeft(find.text('我的')).dx, 16);
    expect(tester.takeException(), isNull);
  });
  test('proxy rejects invalid drafts and enforces port boundaries', () {
    for (final value in [
      'host:0',
      'host:65536',
      'host:-1',
      'host:no',
      'host',
      'http://host:80/path',
      'user:pass@host:80',
      'bad host:80',
    ]) {
      expect(ProxyUtils.parseProxyUrl(value), isNull, reason: value);
    }
    expect(ProxyUtils.parseProxyUrl('127.0.0.1:1'), ('127.0.0.1', 1));
    expect(ProxyUtils.parseProxyUrl('https://proxy.example:65535'), (
      'proxy.example',
      65535,
    ));
  });
  test('favorite aliases do not become update status', () {
    FavoriteRecord record(String subtitle) => FavoriteRecord(
      sourceId: 'fixture',
      mediaId: '1',
      title: '作品',
      cover: '',
      subtitle: subtitle,
      updatedAt: DateTime(2026),
    );
    expect(record('别名 / Alternative title').statusText, isEmpty);
    expect(record('共 12 集').statusText, '共 12 集');
    expect(record('更新至第 8 集').statusText, '更新至第 8 集');
  });
  testWidgets('navigation grows with labels and keeps all tabs tappable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var selected = -1;
    Future<double> render(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildShellTheme(Brightness.dark),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 640),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              bottomNavigationBar: PlayraBottomNav(
                selectedIndex: 0,
                onSelected: (i) => selected = i,
                destinations: [
                  for (final label in ['发现', '日历', '追番', '我的'])
                    PlayraNavDestination(
                      label: label,
                      icon: Icons.movie_outlined,
                      selectedIcon: Icons.movie,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(PlayraBottomNav)).height;
    }

    final normal = await render(1);
    expect(await render(2), greaterThan(normal));
    for (final (index, label) in ['发现', '日历', '追番', '我的'].indexed) {
      await tester.tap(find.text(label));
      expect(selected, index);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'portrait fullscreen transport preserves large text and actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: PlayerTransportBar(
                  compact: false,
                  playPause: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.pause),
                  ),
                  nextEpisode: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.skip_next),
                  ),
                  progressBuilder: (_) => const Placeholder(),
                  timeLabel: const Text(
                    '12:00 / 24:00',
                    style: TextStyle(fontSize: 12),
                  ),
                  timeBesideProgress: true,
                  controls: Row(
                    children: [
                      const Spacer(),
                      TextButton(onPressed: () {}, child: const Text('1.0×')),
                      TextButton(onPressed: () {}, child: const Text('选集')),
                    ],
                  ),
                  fullscreen: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.fullscreen_exit),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('12:00 / 24:00'), findsOneWidget);
      expect(find.text('选集'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
