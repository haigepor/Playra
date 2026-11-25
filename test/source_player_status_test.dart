import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/core/media_source.dart';
import 'package:kazumi/pages/player/source_player_page.dart';

Widget _panel({
  required Size size,
  required double textScale,
  required String title,
  String? message,
  VoidCallback? onPrimary,
  VoidCallback? onSecondary,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: PlayerStatusOverlay(
              icon: title == '播放失败'
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              title: title,
              message: message,
              primaryLabel: title == '播放失败' ? '重试' : '重播',
              primaryIcon: Icons.refresh_rounded,
              onPrimary: onPrimary,
              secondaryLabel: title == '播放失败' ? '切换线路' : '选集',
              secondaryIcon: Icons.playlist_play_rounded,
              onSecondary: onSecondary,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('playback source errors never expose raw URLs or tokens', () {
    for (final kind in MediaSourceErrorKind.values) {
      final message = playbackSourceErrorMessage(
        MediaSourceException(kind, 'https://example.test/video?token=secret'),
      );
      expect(message, isNot(contains('https://')));
      expect(message, isNot(contains('secret')));
    }
    expect(
      playbackSourceErrorMessage(
        const MediaSourceException(MediaSourceErrorKind.vipRequired, 'private'),
      ),
      '该剧集需要会员',
    );
    expect(
      playbackSourceErrorMessage(
        const MediaSourceException(MediaSourceErrorKind.expired, 'private'),
      ),
      '播放地址已失效，请重试',
    );
  });

  for (final size in [
    const Size(320, 132),
    const Size(360, 180),
    const Size(760, 360),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'error state is scrollable and actionable at $size scale $scale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(800, 800);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          var retries = 0;
          var switches = 0;
          const reason = '当前线路无法加载，请稍后重试。';
          await tester.pumpWidget(
            _panel(
              size: size,
              textScale: scale,
              title: '播放失败',
              message: reason,
              onPrimary: () => retries++,
              onSecondary: () => switches++,
            ),
          );
          expect(find.text('播放失败'), findsOneWidget);
          expect(find.text(reason), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('重试'));
          await tester.tap(find.text('重试'));
          await tester.ensureVisible(find.text('切换线路'));
          await tester.tap(find.text('切换线路'));
          expect(retries, 1);
          expect(switches, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'long failure reason and retry remain reachable on narrow screens',
    (tester) async {
      var retries = 0;
      const reason = '播放失败：网络请求超时，请检查网络连接或稍后再试。播放失败：网络请求超时，请检查网络连接或稍后再试。';
      await tester.pumpWidget(
        _panel(
          size: const Size(224, 120),
          textScale: 2,
          title: '播放失败',
          message: reason,
          onPrimary: () => retries++,
        ),
      );
      await tester.ensureVisible(find.text('重试'));
      await tester.tap(find.text('重试'));
      expect(retries, 1);
      expect(find.text(reason), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failure card does not stretch across the video height', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panel(
        size: const Size(760, 360),
        textScale: 1,
        title: '播放失败',
        message: '暂无可播放剧集',
        onPrimary: () {},
      ),
    );
    final card = tester.getSize(
      find.byKey(const ValueKey('player-status-card')),
    );
    expect(card.width, lessThanOrEqualTo(360));
    expect(card.height, lessThan(260));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable failure actions are absent', (tester) async {
    await tester.pumpWidget(
      _panel(
        size: const Size(320, 180),
        textScale: 1,
        title: '播放失败',
        message: '没有可用线路',
      ),
    );
    expect(find.text('没有可用线路'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.text('切换线路'), findsNothing);
  });

  for (final title in ['本集播完', '已播至末集']) {
    testWidgets('$title exposes replay and episode actions', (tester) async {
      var replay = 0;
      var episodes = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _panel(
          size: const Size(320, 180),
          textScale: 1,
          title: title,
          onPrimary: () => replay++,
          onSecondary: () => episodes++,
        ),
      );
      expect(find.bySemanticsLabel(title), findsOneWidget);
      await tester.ensureVisible(find.text('重播'));
      await tester.tap(find.text('重播'));
      await tester.ensureVisible(find.text('选集'));
      await tester.tap(find.text('选集'));
      expect(replay, 1);
      expect(episodes, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
