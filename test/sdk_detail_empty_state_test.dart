import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/pages/sdk_player_detail_page.dart';
import 'package:kazumi/services/source/miomedia/miomedia_playback_provider.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';

Map<String, dynamic> _emptyDetail() => {
  'data': {
    'video': {
      'id': '2018',
      'title': '空线路电影',
      'categoryName': '电影大全',
      'player': <Object>[],
    },
  },
};

Future<void> _mount(WidgetTester tester, MioMediaService service) =>
    tester.pumpWidget(
      MaterialApp(
        home: SdkDetailPage(
          entry: SdkPlaybackEntry(
            title: '空线路电影',
            sources: [
              SdkSourceBinding(
                provider: MioSdkPlaybackProvider(service),
                contentId: '2018',
              ),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'pending detail becomes a real empty state without stale loading or preparation guidance',
    (tester) async {
      final response = Completer<Map<String, dynamic>>();
      final calls = <String>[];
      final service = MioMediaService(
        request: (operation, payload, cancel) {
          calls.add(operation);
          return response.future;
        },
      );
      addTearDown(service.dispose);
      await _mount(tester, service);
      expect(find.text('自动 · 正在获取线路'), findsOneWidget);
      expect(find.text('该作品暂无播放线路'), findsNothing);
      expect(find.text('选择剧集后准备播放链接'), findsNothing);

      response.complete(_emptyDetail());
      await tester.pumpAndSettle();
      expect(find.text('自动 · 暂无播放线路'), findsOneWidget);
      expect(find.text('该作品暂无播放线路'), findsOneWidget);
      expect(find.text('自动 · 正在获取线路'), findsNothing);
      expect(find.text('选择剧集后准备播放链接'), findsNothing);
      expect(calls, ['detail'], reason: '真实空线路不能伪造线路或调用解析');
      final selector = tester.widget<InkWell>(
        find.byKey(const ValueKey('sdk-line-selector')),
      );
      expect(selector.onTap, isNull);
      final play = tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byTooltip('播放当前选集'),
              matching: find.byType(IconButton),
            )
            .first,
      );
      expect(play.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'detail failure is distinct from empty and retry can finish empty',
    (tester) async {
      final calls = <String>[];
      final service = MioMediaService(
        request: (operation, payload, cancel) async {
          calls.add(operation);
          if (calls.length == 1) throw StateError('offline');
          return _emptyDetail();
        },
      );
      addTearDown(service.dispose);
      await _mount(tester, service);
      await tester.pumpAndSettle();
      expect(find.text('作品资料加载失败，请重试'), findsOneWidget);
      expect(find.text('自动 · 线路获取失败'), findsOneWidget);
      expect(find.text('该作品暂无播放线路'), findsNothing);
      expect(find.text('自动 · 正在获取线路'), findsNothing);
      expect(find.text('选择剧集后准备播放链接'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, '重试'));
      await tester.pumpAndSettle();
      expect(find.text('作品资料加载失败，请重试'), findsNothing);
      expect(find.text('自动 · 暂无播放线路'), findsOneWidget);
      expect(find.text('该作品暂无播放线路'), findsOneWidget);
      expect(calls, ['detail', 'detail']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
