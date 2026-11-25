import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/pages/discover/home_sections.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';

MediaSection _section({int count = 6}) {
  return MediaSection(
    id: 'hot',
    title: '热门番剧',
    layout: MediaSectionLayout.grid,
    items: [
      for (var i = 0; i < count; i++)
        MediaItem(
          key: MediaKey(sourceId: 'fake', mediaId: '$i'),
          title: '作品 $i',
          subtitle: '更新至 ${i + 1} 集',
          cover: '',
        ),
    ],
    ranked: true,
    tabs: const ['热播榜'],
  );
}

Widget _harness(
  HomeLayoutMetrics layout, {
  MediaSection? section,
  ValueChanged<MediaItem>? onTap,
  double textScale = 1,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: HomeSectionGrid(
          layout: layout,
          section: section ?? _section(),
          onTap: onTap ?? (_) {},
          onMore: () {},
        ),
      ),
    ),
  );
}

const _longTitle = '这是一个非常非常长的作品名称用于检查海报卡片标题是否单行省略';
const _longStatus = '更新至 123456789 集特别长的更新状态文字';

MediaSection _posterSection({required bool ranked}) => MediaSection(
  id: 'poster-test',
  title: '测试栏目',
  layout: MediaSectionLayout.grid,
  ranked: ranked,
  items: const [
    MediaItem(
      key: MediaKey(sourceId: 'fake', mediaId: 'poster'),
      title: _longTitle,
      subtitle: _longStatus,
      year: 2024,
      area: '日本',
    ),
  ],
);

void main() {
  for (final ranked in [true, false]) {
    testWidgets(
      'poster status is inside cover and rank follows ranked=$ranked',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            HomeLayoutMetrics.phone,
            section: _posterSection(ranked: ranked),
          ),
        );
        final cover = tester.getRect(find.byType(MediaCoverImage));
        final status = tester.getRect(find.text(_longStatus));
        expect(cover.contains(status.topLeft), isTrue);
        expect(
          cover.contains(status.bottomRight - const Offset(0.1, 0.1)),
          isTrue,
        );
        expect(find.text('01'), ranked ? findsOneWidget : findsNothing);
        if (ranked) {
          final rank = tester.getRect(find.text('01'));
          expect(cover.contains(rank.center), isTrue);
          expect(rank.overlaps(status), isFalse);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final device in <(String, Size, HomeLayoutMetrics)>[
    ('phone', const Size(360, 800), HomeLayoutMetrics.phone),
    ('tablet', const Size(1024, 768), HomeLayoutMetrics.tabletLandscape),
  ]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('${device.$1} long poster text at scale $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(device.$2);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _harness(
            device.$3,
            section: _posterSection(ranked: true),
            textScale: scale,
          ),
        );
        expect(tester.takeException(), isNull);
        final title = tester.widget<Text>(find.text(_longTitle));
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
      });
    }
  }

  testWidgets('poster exposes its full label and activates the selected item', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    MediaItem? selected;
    await tester.pumpWidget(
      _harness(
        HomeLayoutMetrics.phone,
        section: _posterSection(ranked: false),
        onTap: (item) => selected = item,
      ),
    );
    final card = find.bySemanticsLabel('查看 $_longTitle，$_longStatus');
    expect(card, findsOneWidget);
    expect(
      tester.getSemantics(card),
      matchesSemantics(
        label: '查看 $_longTitle，$_longStatus',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text(_longTitle));
    expect(selected?.key, const MediaKey(sourceId: 'fake', mediaId: 'poster'));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('poster semantics use metadata when status is absent', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const section = MediaSection(
      id: 'metadata',
      title: '测试栏目',
      layout: MediaSectionLayout.grid,
      items: [
        MediaItem(
          key: MediaKey(sourceId: 'fake', mediaId: 'metadata'),
          title: '作品名称',
          year: 2024,
          area: '日本',
        ),
      ],
    );
    await tester.pumpWidget(
      _harness(HomeLayoutMetrics.phone, section: section),
    );
    expect(find.bySemanticsLabel('查看 作品名称，2024 · 日本'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('phone section exposes the full poster rail', (tester) async {
    await tester.pumpWidget(_harness(HomeLayoutMetrics.phone));
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('作品 5'),
      find.byType(ListView),
      const Offset(-200, 0),
    );
    expect(find.text('作品 5'), findsOneWidget);
    expect(find.text('热门番剧'), findsOneWidget);
    expect(find.text('6 部'), findsNothing);
    expect(find.text('更多'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet landscape section exposes the full poster rail', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(HomeLayoutMetrics.tabletLandscape));
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('作品 5'),
      find.byType(ListView),
      const Offset(-160, 0),
    );
    expect(find.text('作品 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
