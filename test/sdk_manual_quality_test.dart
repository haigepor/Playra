import 'dart:async';
import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/storage/sdk_library_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/pages/sdk_player_detail_page.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';
import 'package:kazumi/services/source/sdk_playback_provider.dart';

class _Sdk extends SdkPlaybackProvider {
  @override
  String get id => 'lumina';
  @override
  String get name => 'Lumina';
  @override
  bool get supportsQualities => true;
  final calls = <String>[];
  bool unknown = false;
  bool rejected = false;
  bool firstEpisodeOnly1080 = false;
  Completer<void>? gate;
  @override
  Future<SdkVideo> detail(String id, {CancelToken? cancel}) async =>
      SdkVideoData(
        id: id,
        title: '画质切换作品',
        lines: const [SdkLine('a', '线路A'), SdkLine('b', '线路B')],
      );
  @override
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) async => [
    SdkEpisode(number: 12, name: '第12集', code: code),
    SdkEpisode(number: 99, name: '第99集', code: code),
  ];
  @override
  Future<List<SdkQuality>> qualities(
    String id,
    String code,
    int episode, {
    CancelToken? cancel,
  }) async => unknown
      ? const [SdkQuality('unknown')]
      : firstEpisodeOnly1080 && episode == 12
      ? const [SdkQuality('1080p', height: 1080)]
      : const [
          SdkQuality('1080p', height: 1080),
          SdkQuality('2160p', height: 2160),
        ];
  @override
  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  }) async {
    calls.add('$code:$episode:$quality');
    if (quality == '1080p') await gate?.future;
    if (rejected)
      return {'status': 'unavailable', 'error': 'CLIENT_PARSE_REJECTED'};
    return {
      'status': 'ready',
      'selection': {'videoId': id, 'code': code, 'episodeNum': episode},
      'media': {'url': 'https://media.example/$code/$episode/$quality.mp4'},
    };
  }
}

class _ManyEpisodesSdk extends _Sdk {
  @override
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) async => [
    for (var number = 1; number <= 99; number++)
      SdkEpisode(number: number, name: '第$number集', code: code),
  ];
}

Future<void> _mount(
  WidgetTester tester,
  _Sdk sdk, {
  double scale = 1,
  SdkLibraryStore? library,
}) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: SdkDetailPage(
        library: library,
        entry: SdkPlaybackEntry(
          title: '作品',
          sources: [SdkSourceBinding(provider: sdk, contentId: '42')],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'saved SDK episode and manual line prepare without writing new history',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('sdk-detail-history'),
      ))!;
      Hive.init(directory.path);
      final box = (await tester.runAsync(
        () => Hive.openBox<String>('sdk-widget'),
      ))!;
      final library = SdkLibraryStore(box: box, privateMode: () => false);
      await tester.pump();
      addTearDown(() async {
        library.dispose();
        await tester.runAsync(() async {
          await Hive.close();
          await directory.delete(recursive: true);
        });
      });
      await tester.runAsync(
        () => library.record(
          providerId: 'lumina',
          video: const SdkVideoData(id: '42', title: '作品'),
          episode: const SdkEpisode(number: 99, name: '第99集', code: 'b'),
          position: const Duration(seconds: 46),
          duration: const Duration(minutes: 20),
          automatic: false,
          qualityCode: '1080p',
        ),
      );
      final before = library.histories.single.lastWatch!.updatedAt;
      final sdk = _Sdk();
      await _mount(tester, sdk, library: library);
      expect(sdk.calls.last, 'b:99:1080p');
      expect(find.text('手动 · 线路B'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '第99集'), findsOneWidget);
      expect(library.histories.single.lastWatch!.updatedAt, before);
      expect(find.textContaining('0:46'), findsOneWidget);
      await _tap(tester, find.byTooltip('设置收藏状态'));
      expect(find.text('在看'), findsOneWidget);
      expect(find.text('想看'), findsOneWidget);
      expect(library.histories.single.lastWatch!.position.inSeconds, 46);
    },
  );
  testWidgets('prepared episode 99 remains visible before explicit play', (
    tester,
  ) async {
    final sdk = _ManyEpisodesSdk();
    await _mount(tester, sdk);
    await _tap(tester, find.text('全部 99集 ›'));
    await _tap(tester, find.text('升序'));
    await _tap(tester, find.text('第99集').last);
    expect(find.widgetWithText(OutlinedButton, '第99集'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '第1集'), findsNothing);
    expect(sdk.calls.last.endsWith(':99:2160p'), isTrue);
    expect(find.text('播放链接已准备，点击播放'), findsOneWidget);
  });
  testWidgets(
    'manual quality retains episode 99 and independent manual line lock',
    (tester) async {
      final sdk = _Sdk();
      await _mount(tester, sdk);
      expect(sdk.calls.last, 'a:12:2160p');
      await _tap(tester, find.widgetWithText(OutlinedButton, '第99集'));
      await _tap(tester, find.byKey(const ValueKey('sdk-line-selector')));
      await _tap(tester, find.text('线路B'));
      expect(sdk.calls.last, 'b:99:2160p');
      await _tap(tester, find.byKey(const ValueKey('sdk-quality-1080p')));
      expect(sdk.calls.last, 'b:99:1080p');
      expect(find.text('手动 · 线路B'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('sdk-quality-auto')));
      expect(sdk.calls.last, 'b:99:2160p');
      expect(find.text('手动 · 线路B'), findsOneWidget, reason: '恢复自动画质不能解除手动锁线');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('old single links expose no invented 4K or 1080p buttons', (
    tester,
  ) async {
    await _mount(tester, _Sdk()..unknown = true);
    expect(find.byKey(const ValueKey('sdk-quality-auto')), findsNothing);
    expect(find.byKey(const ValueKey('sdk-quality-2160p')), findsNothing);
    expect(find.byKey(const ValueKey('sdk-quality-1080p')), findsNothing);
    expect(find.text('来源未声明画质'), findsOneWidget);
  });

  testWidgets(
    'parser rejection keeps line lock and exposes recovery without a fake direct link',
    (tester) async {
      final sdk = _Sdk()
        ..unknown = true
        ..rejected = true;
      await _mount(tester, sdk);
      expect(find.text('来源未声明画质，使用原始直链'), findsNothing);
      expect(find.byKey(const ValueKey('sdk-quality-auto')), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('sdk-line-selector')));
      await _tap(tester, find.text('线路B'));
      expect(find.text('手动 · 线路B'), findsOneWidget);
      expect(find.text('该线路暂未提供可播放地址，可重试或切换线路。'), findsOneWidget);
      await _tap(tester, find.widgetWithText(TextButton, '切换线路'));
      expect(find.text('线路A'), findsOneWidget);
      expect(find.text('手动 · 线路B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('quality controls fit 320px with enlarged text', (tester) async {
    await _mount(tester, _Sdk(), scale: 1.8);
    expect(find.byKey(const ValueKey('sdk-quality-2160p')), findsOneWidget);
    expect(find.byKey(const ValueKey('sdk-quality-1080p')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual resolution persists on episode changes and missing tiers ask for automatic selection',
    (tester) async {
      final sdk = _Sdk()..firstEpisodeOnly1080 = true;
      await _mount(tester, sdk);
      await _tap(tester, find.widgetWithText(OutlinedButton, '第99集'));
      await _tap(tester, find.byKey(const ValueKey('sdk-quality-2160p')));
      final requestsBeforeMissing = sdk.calls.length;
      await _tap(tester, find.widgetWithText(OutlinedButton, '第12集'));
      expect(
        sdk.calls.length,
        requestsBeforeMissing,
        reason: '缺少手动4K不能偷偷打开1080p或首集',
      );
      expect(find.text('当前集或线路没有所选画质，请选择其他画质或自动。'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('sdk-quality-auto')));
      expect(sdk.calls.last.endsWith(':12:1080p'), isTrue);
    },
  );

  testWidgets('late 1080p preparation cannot overwrite a newer 4K selection', (
    tester,
  ) async {
    final sdk = _Sdk();
    await _mount(tester, sdk);
    sdk.gate = Completer<void>();
    final option = find.byKey(const ValueKey('sdk-quality-1080p'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final newer = find.byKey(const ValueKey('sdk-quality-2160p'));
    await tester.ensureVisible(newer);
    await tester.tap(newer);
    await tester.pumpAndSettle();
    sdk.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(newer).selected, isTrue);
    expect(tester.widget<ChoiceChip>(option).selected, isFalse);
    expect(find.text('播放链接已准备，点击播放'), findsOneWidget);
  });
}
