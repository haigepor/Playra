import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/pages/sdk_player_detail_page.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';
import 'package:kazumi/services/source/sdk_playback_provider.dart';

/// 三条线路：有当前集 / 集号对不上 / 空目录。
class _SplitSdk extends SdkPlaybackProvider {
  @override
  String get id => 'split-sdk';
  @override
  String get name => 'Split';
  @override
  Future<SdkVideo> detail(String id, {CancelToken? cancel}) async =>
      SdkVideoData(
        id: id,
        title: '分线路作品',
        lines: const [
          SdkLine('a', '有当前集'),
          SdkLine('b', '缺当前集'),
          SdkLine('c', '空目录'),
        ],
      );
  @override
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) async => switch (code) {
    'a' => const [SdkEpisode(number: 1, name: '第1集', code: 'a')],
    'b' => const [SdkEpisode(number: 9, name: '第9集', code: 'b')],
    _ => const [],
  };
  @override
  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  }) async => {'status': 'unavailable'};
}

Future<void> _mount(WidgetTester tester, SdkPlaybackProvider sdk) async {
  tester.view.physicalSize = const Size(360, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: SdkDetailPage(
        entry: SdkPlaybackEntry(
          title: '分线路作品',
          autoPlay: false,
          sources: [SdkSourceBinding(provider: sdk, contentId: '7')],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('sdk-line-selector')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lines without the current episode stay out of the sheet', (
    tester,
  ) async {
    await _mount(tester, _SplitSdk());
    await _openSheet(tester);
    expect(find.text('有当前集'), findsOneWidget);
    // 点了也播不了的线路不再罗列，避免用户反复试错。
    expect(find.text('缺当前集'), findsNothing);
    expect(find.text('空目录'), findsNothing);
    expect(find.text('没有对应当前集'), findsNothing);
  });
}
