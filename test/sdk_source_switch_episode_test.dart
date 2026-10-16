import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/pages/sdk_player_detail_page.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';
import 'package:kazumi/services/source/sdk_playback_provider.dart';

class _EpisodeSdk extends SdkPlaybackProvider {
  _EpisodeSdk(this.id, this.directory);

  @override
  final String id;
  final List<SdkEpisode> directory;
  final played = <String>[];
  final loadedDetails = <String>[];

  @override
  String get name => id;

  String get lineCode => '$id-line';
  String get contentId => '$id/video';

  @override
  Future<SdkVideo> detail(String id, {CancelToken? cancel}) async {
    loadedDetails.add(id);
    return SdkVideoData(
      id: id,
      title: '跨来源剧集',
      categoryName: '电视剧',
      lines: [SdkLine(lineCode, '播放线路')],
    );
  }

  @override
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) async => directory;

  @override
  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  }) async {
    played.add('$id|$code|$episode');
    // 覆盖真实页面的选集与切源，只在 SDK 媒体边界停止，避免启动解码器。
    return {'status': 'unavailable'};
  }
}

_EpisodeSdk _originalSdk() => _EpisodeSdk('sdk_original', const [
  SdkEpisode(number: 12, name: '第12集', code: 'sdk_original-line'),
  SdkEpisode(number: 14, name: '第14集', code: 'sdk_original-line'),
]);

Future<void> _mountAndSelectEpisode14(
  WidgetTester tester,
  _EpisodeSdk original,
  _EpisodeSdk destination,
) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(
    MaterialApp(
      home: SdkDetailPage(
        entry: SdkPlaybackEntry(
          title: '跨来源剧集',
          autoPlay: false,
          sources: [
            SdkSourceBinding(provider: original, contentId: original.contentId),
            SdkSourceBinding(
              provider: destination,
              contentId: destination.contentId,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(original.played, ['sdk_original/video|sdk_original-line|12']);
  original.played.clear();
  expect(destination.played, isEmpty);

  final episode14 = find.widgetWithText(OutlinedButton, '第14集');
  await tester.scrollUntilVisible(
    episode14,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(episode14);
  await tester.pumpAndSettle();
  expect(original.played, ['sdk_original/video|sdk_original-line|14']);
  expect(tester.takeException(), isNull);
}

Future<void> _switchSource(WidgetTester tester, _EpisodeSdk destination) async {
  final source = find.widgetWithText(ChoiceChip, destination.name);
  await tester.scrollUntilVisible(
    source,
    -160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(source);
  await tester.pumpAndSettle();
  expect(destination.loadedDetails, [destination.contentId]);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'switching SDK preserves episode 14 and uses destination identity 914',
    (tester) async {
      final original = _originalSdk();
      final destination = _EpisodeSdk('sdk_destination', const [
        SdkEpisode(number: 912, name: '第12集', code: 'sdk_destination-line'),
        SdkEpisode(number: 914, name: '第14集', code: 'sdk_destination-line'),
      ]);
      await _mountAndSelectEpisode14(tester, original, destination);

      await _switchSource(tester, destination);

      expect(destination.played, [
        'sdk_destination/video|sdk_destination-line|914',
      ], reason: '切换 SDK 应匹配当前第14集，不能播放目标目录首集或沿用旧来源 ID。');
      expect(original.played, ['sdk_original/video|sdk_original-line|14']);
    },
  );

  testWidgets(
    'switching SDK without episode 14 never falls back to its first episode',
    (tester) async {
      final original = _originalSdk();
      final destination = _EpisodeSdk('sdk_destination', const [
        SdkEpisode(number: 912, name: '第12集', code: 'sdk_destination-line'),
        SdkEpisode(number: 913, name: '第13集', code: 'sdk_destination-line'),
      ]);
      await _mountAndSelectEpisode14(tester, original, destination);

      await _switchSource(tester, destination);

      expect(
        destination.played,
        isEmpty,
        reason: '目标 SDK 没有第14集时，应保留明确的手动选择机会，不能悄悄跳到首集。',
      );
      expect(original.played, ['sdk_original/video|sdk_original-line|14']);
    },
  );
}
