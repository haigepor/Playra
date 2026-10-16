import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/pages/sdk_player_detail_page.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';
import 'package:kazumi/services/source/sdk_playback_provider.dart';
import 'package:kazumi/services/source/sdk_playback_coordinator.dart';
import 'package:kazumi/services/source/source_models.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_playing_mark.dart';

class _Sdk extends SdkPlaybackProvider {
  @override
  String get id => 'preparation-sdk';
  @override
  String get name => 'Preparation';
  final resolved = <int>[];
  Completer<void>? firstGate;
  @override
  Future<SdkVideo> detail(String id, {CancelToken? cancel}) async =>
      SdkVideoData(id: id, title: '准备作品', lines: const [SdkLine('a', '线路A')]);
  @override
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) async => const [
    SdkEpisode(number: 1, name: '第1集', code: 'a'),
    SdkEpisode(number: 2, name: '第2集', code: 'a'),
  ];
  @override
  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  }) async {
    resolved.add(episode);
    if (episode == 1) await firstGate?.future;
    return {
      'status': 'ready',
      'selection': {'videoId': id, 'code': code, 'episodeNum': episode},
      'media': {
        'url': 'https://media.example.test/$episode.mp4',
        'headers': {'User-Agent': ''},
        'format': 'auto',
      },
    };
  }
}

class _OpaqueSdk extends _Sdk {
  final references = <String>[];
  static const parts = [
    SdkEpisode(number: null, name: '特别篇A', code: 'a', reference: '特别篇A 原版'),
    SdkEpisode(number: null, name: '特别篇B', code: 'a', reference: '特别篇B 原版'),
  ];
  @override
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) async => parts;
  @override
  Future<Map<String, dynamic>> playEpisode(
    String id,
    String code,
    SdkEpisode episode, {
    String? quality,
    CancelToken? cancel,
  }) async {
    references.add(episode.reference!);
    return {
      'status': 'ready',
      'selection': {
        'videoId': id,
        'code': code,
        'episodeRef': episode.reference,
      },
      'media': {
        'url':
            'https://media.example.test/${Uri.encodeComponent(episode.reference!)}.mp4',
      },
    };
  }
}

void main() {
  const episode = SdkEpisode(number: 1, name: '第1集', code: 'a');
  const lines = [SdkLine('a', '线路A')];

  test(
    'explicit play consumes a fresh prepared link and preserves empty UA',
    () async {
      final sdk = _Sdk();
      final coordinator = SdkPlaybackCoordinator('work', sdk);
      addTearDown(coordinator.dispose);
      final prepared = await coordinator.preparePlayback(
        episode,
        lines,
        cancel: CancelToken(),
        onAttempt: (_, _, _) {},
      );
      expect(prepared.status, 'prepared');
      expect(sdk.resolved, [1]);
      var opened = 0;
      final played = await coordinator.playAutomatic(
        episode,
        lines,
        cancel: CancelToken(),
        onAttempt: (_, _, _) {},
        prepared: prepared.prepared,
        open: (_, media, _) async {
          opened++;
          expect(media['headers'], {'User-Agent': ''});
          return true;
        },
      );
      expect(played.status, 'ready');
      expect(opened, 1);
      expect(sdk.resolved, [1], reason: '点击不应重复解析未过期直链');
    },
  );

  test('expired preparation is resolved again before opening media', () async {
    final sdk = _Sdk();
    var now = DateTime(2026, 10, 16);
    final coordinator = SdkPlaybackCoordinator('work', sdk, now: () => now);
    addTearDown(coordinator.dispose);
    final prepared = await coordinator.preparePlayback(
      episode,
      lines,
      cancel: CancelToken(),
      onAttempt: (_, _, _) {},
    );
    now = now.add(const Duration(seconds: 31));
    final result = await coordinator.playAutomatic(
      episode,
      lines,
      cancel: CancelToken(),
      onAttempt: (_, _, _) {},
      prepared: prepared.prepared,
      open: (_, _, _) async => true,
    );
    expect(result.status, 'ready');
    expect(sdk.resolved, [1, 1]);
  });

  test(
    'expired media rejection refreshes once inside the locked line',
    () async {
      final sdk = _Sdk();
      final coordinator = SdkPlaybackCoordinator('work', sdk);
      addTearDown(coordinator.dispose);
      final prepared = await coordinator.preparePlayback(
        episode,
        lines,
        cancel: CancelToken(),
        onAttempt: (_, _, _) {},
        manual: true,
      );
      var opened = 0;
      final result = await coordinator.playAutomatic(
        episode,
        lines,
        cancel: CancelToken(),
        onAttempt: (_, _, _) {},
        manual: true,
        prepared: prepared.prepared,
        open: (_, _, _) async {
          opened++;
          throw const SourceException('EXPIRED', 'HTTP 403');
        },
      );
      expect(result.status, 'unavailable');
      expect(opened, 2);
      expect(sdk.resolved, [1, 1], reason: '同线至多刷新一次，不无限循环');
    },
  );

  test(
    'opaque parts cannot consume another null-number episode preparation',
    () async {
      final sdk = _OpaqueSdk();
      final coordinator = SdkPlaybackCoordinator('work', sdk);
      addTearDown(coordinator.dispose);
      final prepared = await coordinator.preparePlayback(
        _OpaqueSdk.parts.first,
        lines,
        cancel: CancelToken(),
        onAttempt: (_, _, _) {},
      );
      final result = await coordinator.playAutomatic(
        _OpaqueSdk.parts.last,
        lines,
        cancel: CancelToken(),
        onAttempt: (_, _, _) {},
        prepared: prepared.prepared,
        open: (selected, media, _) async {
          expect(selected.reference, '特别篇B 原版');
          expect(Uri.decodeFull(media['url']), contains('特别篇B 原版'));
          return true;
        },
      );
      expect(result.status, 'ready');
      expect(sdk.references, ['特别篇A 原版', '特别篇B 原版']);
      expect(sdk.resolved, isEmpty, reason: '不把原文part退化成伪造集数');
    },
  );

  test(
    'cancelled pending preparation cannot return late playable media',
    () async {
      final sdk = _Sdk()..firstGate = Completer<void>();
      final coordinator = SdkPlaybackCoordinator('work', sdk);
      addTearDown(coordinator.dispose);
      final cancel = CancelToken();
      final pending = coordinator.preparePlayback(
        episode,
        lines,
        cancel: cancel,
        onAttempt: (_, _, _) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(sdk.resolved, [1]);
      cancel.cancel('page disposed');
      sdk.firstGate!.complete();
      final result = await pending;
      expect(result.status, 'cancelled');
      expect(result.prepared, isNull);
    },
  );

  testWidgets('detail prepares a real link without installing a media player', (
    tester,
  ) async {
    final sdk = _Sdk();
    await tester.pumpWidget(
      MaterialApp(
        home: SdkDetailPage(
          entry: SdkPlaybackEntry(
            title: '准备作品',
            autoPlay: false,
            sources: [SdkSourceBinding(provider: sdk, contentId: 'work')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sdk.resolved, [1], reason: '禁用自动播放仍须解析直链');
    expect(find.text('播放链接已准备，点击播放'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '准备阶段不能访问播放器、原生模块或媒体打开');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'choosing an episode before playback only prepares the chosen identity',
    (tester) async {
      final sdk = _Sdk();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: SdkDetailPage(
            entry: SdkPlaybackEntry(
              title: '准备作品',
              sources: [SdkSourceBinding(provider: sdk, contentId: 'work')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final second = find.widgetWithText(OutlinedButton, '第2集');
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(sdk.resolved, [1, 2]);
      expect(find.text('播放链接已准备，点击播放'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '未播放的选集不能访问原生播放器或媒体open');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late preparation cannot overwrite a newly selected episode', (
    tester,
  ) async {
    final sdk = _Sdk()..firstGate = Completer<void>();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SdkDetailPage(
          entry: SdkPlaybackEntry(
            title: '准备作品',
            sources: [SdkSourceBinding(provider: sdk, contentId: 'work')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sdk.resolved, [1]);
    final second = find.widgetWithText(OutlinedButton, '第2集');
    await tester.ensureVisible(second);
    await tester.tap(second);
    await tester.pumpAndSettle();
    sdk.firstGate!.complete();
    await tester.pumpAndSettle();
    expect(sdk.resolved, [1, 2]);
    expect(
      find.descendant(of: second, matching: find.byType(MioPlayingMark)),
      findsOneWidget,
      reason: '旧请求完成后仍选中第2集',
    );
    expect(
      find.descendant(
        of: find.widgetWithText(OutlinedButton, '第1集'),
        matching: find.byType(MioPlayingMark),
      ),
      findsNothing,
    );
    expect(find.text('播放链接已准备，点击播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
