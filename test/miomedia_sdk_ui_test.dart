import 'dart:async';
import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_detail_page.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/presentation/modern/player/sdk_source_widgets.dart';

const _selectorKey = ValueKey('sdk-line-selector');

class _SourceFixture {
  _SourceFixture({
    required this.movie,
    this.lineCount = 2,
    this.firstDirectoryGate,
  });

  final bool movie;
  final int lineCount;
  final Completer<void>? firstDirectoryGate;
  final calls = <Map<String, dynamic>>[];

  String code(int index) => 'sdk_line_${index + 1}';
  String label(int index) => '接口新增线路${index + 1}';

  Map<String, dynamic> get raw => {
    'id': '9007199254740993',
    'title': movie ? '单集电影测试' : '剧集匹配测试',
    'categoryName': movie ? '电影大全' : '电视剧大全',
    'player': List.generate(
      lineCount,
      (index) => {'playerCode': code(index), 'playerName': label(index)},
    ),
  };

  late final service = MioMediaService(
    request: (operation, payload, cancel) async {
      calls.add({'operation': operation, ...payload});
      final line = payload['code'] as String?;
      final first = line == code(0);
      if (operation == 'episodes' && first && firstDirectoryGate != null) {
        await firstDirectoryGate!.future;
      }
      return {
        'data': switch (operation) {
          'detail' => {'video': raw},
          'episodes' => {
            'episodes': movie
                ? [
                    {
                      'episodeNum': first ? 12 : 42,
                      'displayName': first ? '正片' : '高清完整版',
                      'code': line,
                    },
                  ]
                : [
                    {
                      'episodeNum': first ? 12 : 912,
                      'displayName': '第12集',
                      'code': line,
                    },
                    {
                      'episodeNum': first ? 14 : 914,
                      'displayName': '第14集',
                      'code': line,
                    },
                  ],
          },
          'qualities' => {
            'qualities': [
              {'quality': '1080p', 'label': '超清'},
            ],
          },
          // 不提供媒体地址，测试覆盖真实页面与 SDK 请求边界而不启动解码器。
          'play' => {'status': 'unavailable'},
          _ => {},
        },
      };
    },
  );

  List<Map<String, dynamic>> get playCalls =>
      calls.where((entry) => entry['operation'] == 'play').toList();
}

Future<void> _mount(
  WidgetTester tester,
  _SourceFixture fixture, {
  double scale = 1,
  bool autoPlay = false,
  bool settle = true,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    fixture.service.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: MioDetailPage(
        item: MioVideo.fromJson(fixture.raw),
        service: fixture.service,
        autoPlay: autoPlay,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _openLines(WidgetTester tester, {bool settle = true}) async {
  final selector = find.byKey(_selectorKey);
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }
}

Future<void> _selectLine(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  await _openLines(tester, settle: settle);
  final option = find.text(label).last;
  await tester.ensureVisible(option);
  await tester.tap(option);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'automatic preparation requests other lines while the first waits',
    (tester) async {
      final firstDirectory = Completer<void>();
      final fixture = _SourceFixture(
        movie: false,
        firstDirectoryGate: firstDirectory,
      );
      try {
        await _mount(tester, fixture, autoPlay: true, settle: false);

        expect(firstDirectory.isCompleted, isFalse);
        expect(
          fixture.calls.where(
            (entry) =>
                entry['operation'] == 'episodes' &&
                entry['code'] == fixture.code(0),
          ),
          isNotEmpty,
        );
        expect(
          fixture.calls.where(
            (entry) =>
                entry['operation'] == 'episodes' &&
                entry['code'] == fixture.code(1),
          ),
          isNotEmpty,
          reason: '首线路目录仍等待时，其他线路必须已经并发请求。',
        );
      } finally {
        firstDirectory.complete();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late initial directory cannot restart a manually selected episode',
    (tester) async {
      final firstDirectory = Completer<void>();
      final fixture = _SourceFixture(
        movie: false,
        firstDirectoryGate: firstDirectory,
      );
      try {
        await _mount(tester, fixture, autoPlay: true, settle: false);
        await _selectLine(tester, fixture.label(1), settle: false);
        final episode = find.widgetWithText(OutlinedButton, '第14集');
        await tester.ensureVisible(episode);
        await tester.tap(episode);
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump();
        expect(fixture.playCalls, isNotEmpty);
        expect(fixture.playCalls.last['code'], fixture.code(1));
        expect(fixture.playCalls.last['episodeNum'], 914);

        firstDirectory.complete();
        await tester.pumpAndSettle();

        expect(fixture.playCalls.last['code'], fixture.code(1));
        expect(
          fixture.playCalls.last['episodeNum'],
          914,
          reason: '迟到的首次自动加载不得覆盖用户刚选择的第14集。',
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!firstDirectory.isCompleted) firstDirectory.complete();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('SDK is the selected outer playback source, with lines nested', (
    tester,
  ) async {
    final fixture = _SourceFixture(movie: true);
    await _mount(tester, fixture);

    expect(find.text('播放源'), findsOneWidget);
    final provider = find.widgetWithText(ChoiceChip, '影视 · MioMedia');
    expect(provider, findsOneWidget);
    expect(tester.widget<ChoiceChip>(provider).selected, isTrue);
    expect(find.byKey(_selectorKey), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, fixture.label(1)), findsNothing);
    expect(fixture.playCalls, isNotEmpty, reason: '详情自动解析，但解析失败的线路不能标为正在播放');
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatic mode does not mark an unplayed line as current', (
    tester,
  ) async {
    final fixture = _SourceFixture(movie: true);
    final semantics = tester.ensureSemantics();
    try {
      await _mount(tester, fixture);
      await _openLines(tester);
      expect(find.text('当前使用'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(
        tester
            .getSemantics(find.widgetWithText(SdkLineOption, '自动（优选线路）'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      final close = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '关闭线路选择',
        ),
      );
      expect(
        close.color,
        Theme.of(
          tester.element(find.byType(BottomSheet)),
        ).colorScheme.onSurfaceVariant,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('system reduced motion disables sheet transitions', (
    tester,
  ) async {
    final fixture = _SourceFixture(movie: true);
    await _mount(tester, fixture, reducedMotion: true);
    await _openLines(tester);
    final sheetContext = tester.element(find.byType(BottomSheet));
    expect(ModalRoute.of(sheetContext)!.transitionDuration, Duration.zero);
    expect(sdkMotion(sheetContext), Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('line sheet includes automatic mode and all dynamic SDK lines', (
    tester,
  ) async {
    final fixture = _SourceFixture(movie: true, lineCount: 9);
    await _mount(tester, fixture, scale: 2);
    final initialResolves = fixture.playCalls.length;
    await _openLines(tester);

    expect(find.text('自动（优选线路）'), findsOneWidget);
    final sheet = find.byType(BottomSheet);
    final scrollable = find
        .descendant(of: sheet, matching: find.byType(Scrollable))
        .first;
    for (var index = 0; index < fixture.lineCount; index++) {
      final option = find.descendant(
        of: sheet,
        matching: find.text(fixture.label(index)),
      );
      await tester.scrollUntilVisible(option, 160, scrollable: scrollable);
      expect(option, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    final close = find.byTooltip('关闭线路选择');
    expect(close.hitTestable(), findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      fixture.playCalls,
      hasLength(initialResolves),
      reason: '只浏览线路弹层不应额外解析或打开媒体',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual movie line prepares its real episode identity', (
    tester,
  ) async {
    final fixture = _SourceFixture(movie: true);
    await _mount(tester, fixture);
    await _selectLine(tester, fixture.label(0));
    expect(fixture.playCalls, isNotEmpty);
    expect(fixture.playCalls.first['episodeNum'], 12);

    fixture.calls.clear();
    await _selectLine(tester, fixture.label(1));

    expect(fixture.playCalls, isNotEmpty);
    expect(
      fixture.playCalls.every(
        (entry) =>
            entry['videoId'] == fixture.raw['id'] &&
            entry['code'] == fixture.code(1) &&
            entry['episodeNum'] == 42,
      ),
      isTrue,
    );
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual series switch matches the current episode across SDK IDs',
    (tester) async {
      final fixture = _SourceFixture(movie: false);
      await _mount(tester, fixture);
      await _selectLine(tester, fixture.label(0));
      final episode = find.widgetWithText(OutlinedButton, '第14集');
      await tester.ensureVisible(episode);
      await tester.tap(episode);
      await tester.pumpAndSettle();
      expect(fixture.playCalls.last['episodeNum'], 14);

      fixture.calls.clear();
      await _selectLine(tester, fixture.label(1));

      expect(fixture.playCalls, isNotEmpty);
      expect(
        fixture.playCalls.every(
          (entry) =>
              entry['code'] == fixture.code(1) && entry['episodeNum'] == 914,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
