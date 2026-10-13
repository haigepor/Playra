import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/content_search.dart';
import 'package:kazumi/presentation/modern/pages/content_search_screen.dart';

class ScreenProvider extends ContentSearchProvider {
  ScreenProvider(this.id, this.result);
  @override
  final String id;
  @override
  String get name => id;
  @override
  Set<ContentGroup> get groups => {ContentGroup.anime};
  final Future<ContentSearchPage> result;
  @override
  Future<ContentSearchPage> search(ContentQuery q, int page, CancelToken c) =>
      result;
}

void main() {
  testWidgets('series search remains usable with a keyboard at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: ContentSearchScreen(
          initialKeyword: '作品',
          initialGroup: ContentGroup.series,
          providers: [
            ScreenProvider(
              'anime',
              Future.value(const ContentSearchPage([], hasMore: false)),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('an empty filtered page still offers the upstream next page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ContentSearchScreen(
          initialKeyword: '作品',
          providers: [
            ScreenProvider(
              'pages',
              Future.value(const ContentSearchPage([], hasMore: true)),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('继续检索下一页'), findsOneWidget);
  });
  testWidgets(
    'expanded progress for sixteen providers stays within a compact viewport',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: ContentSearchScreen(
            initialKeyword: '作品',
            providers: [
              for (var i = 0; i < 16; i++)
                ScreenProvider(
                  '$i',
                  Future.value(const ContentSearchPage([], hasMore: false)),
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('content-search-progress')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'first result is visible while another provider is still searching',
    (tester) async {
      final slow = Completer<ContentSearchPage>();
      await tester.pumpWidget(
        MaterialApp(
          home: ContentSearchScreen(
            initialKeyword: '作品',
            providers: [
              ScreenProvider(
                'fast',
                Future.value(
                  const ContentSearchPage([
                    ContentHit(
                      providerId: 'fast',
                      contentId: '1',
                      title: '先到的作品',
                      group: ContentGroup.anime,
                    ),
                  ], hasMore: false),
                ),
              ),
              ScreenProvider('slow', slow.future),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('先到的作品'), findsOneWidget);
      expect(find.textContaining('继续检索'), findsOneWidget);
      slow.complete(const ContentSearchPage([], hasMore: false));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'four groups fit at 320px; a reserved group has a distinct empty state',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: ContentSearchScreen(
            initialKeyword: '作品',
            providers: [
              ScreenProvider(
                'anime',
                Future.value(const ContentSearchPage([], hasMore: false)),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('漫剧'));
      await tester.pumpAndSettle();
      expect(find.textContaining('来源尚未接入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
