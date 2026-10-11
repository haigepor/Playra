import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/index_page.dart';
import 'package:kazumi/presentation/interface_page_host.dart';
import 'package:kazumi/presentation/interface_style.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/home/modern_home_view.dart';
import 'package:kazumi/presentation/shared/interface_style_tile.dart';

class _SharedData {
  int savedItems = 7;
}

Module _module(_SharedData shared, {bool preview = false}) => createModule(
  register: (root) {
    root.module(
      createModule(
        path: '/tab',
        register: (c) {
          c.route(
            '/',
            transition: TransitionType.none,
            child: (context, state) => IndexPage(
              location: state.uri.path,
              mobilePageBuilders: [
                for (final page in ['popular', 'timeline', 'collect', 'my'])
                  (_) => preview && page == 'popular'
                      ? const _HomePreview()
                      : _Page(name: 'modern-$page', shared: shared),
              ],
            ),
            children: (sub) {
              for (final page in ['popular', 'timeline', 'collect', 'my']) {
                sub.route(
                  '/$page/',
                  transition: TransitionType.none,
                  child: (context, state) => InterfacePageHost(
                    legacy: (_) => _Page(name: 'legacy-$page', shared: shared),
                    modern: (_) => preview && page == 'popular'
                        ? const _HomePreview()
                        : _Page(name: 'modern-$page', shared: shared),
                  ),
                );
              }
            },
          );
        },
      ),
    );
    root.route(
      '/settings/interface',
      transition: TransitionType.none,
      child: (context, state) =>
          const Scaffold(body: SafeArea(child: InterfaceStyleTile())),
    );
  },
);

class _Page extends StatefulWidget {
  const _Page({required this.name, required this.shared});
  final String name;
  final _SharedData shared;
  @override
  State<_Page> createState() => _PageState();
}

class _HomePreview extends StatefulWidget {
  const _HomePreview();
  @override
  State<_HomePreview> createState() => _HomePreviewState();
}

class _HomePreviewState extends State<_HomePreview> {
  late final controller = ModernHomeController(
    readHistory: () => [],
    loadFeed: (_, _) async => List.generate(
      6,
      (id) => BangumiItem.fromJson({
        'id': id,
        'name': '布局测试番剧 $id',
        'rating': {'score': 8.0},
        'images': <String, String>{},
      }),
    ),
  );
  @override
  void initState() {
    super.initState();
    controller.refresh();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernHomeView(
    controller: controller,
    onSearch: () {},
    onCalendar: () =>
        (rootNavigatorKey.currentContext ?? context).navigate('/tab/timeline/'),
    onBrowse: (_) {},
    onHistory: () {},
    onToggleTheme: () {},
    onDetails: (_) {},
    onResume: (_) {},
  );
}

class _PageState extends State<_Page> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(widget.name),
      Text('shared=${widget.shared.savedItems}'),
      TextButton(
        onPressed: () => setState(() => count++),
        child: Text('local=$count'),
      ),
      TextButton(
        onPressed: () => context.pushNamed('/settings/interface'),
        child: const Text('open-style'),
      ),
    ],
  );
}

Future<void> _mount(
  WidgetTester tester,
  InterfaceStyleController controller, {
  Size size = const Size(390, 844),
  bool preview = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ModularApp(
      module: _module(_SharedData(), preview: preview),
      navigatorKey: rootNavigatorKey,
      initialRoute: '/tab/popular/',
      navigatorObservers: [rootRouteObserver],
      provide: (scoped) =>
          scoped.addChangeNotifier<InterfaceStyleController>(() => controller),
      child: Builder(
        builder: (context) => MaterialApp.router(
          routerConfig: ModularApp.routerConfigOf(context),
          theme: ThemeData(
            colorSchemeSeed: Colors.green,
            fontFamily: 'MI_Sans_Regular',
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: RepaintBoundary(
              key: const ValueKey('preview-boundary'),
              child: child!,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

InterfaceStyleController _controller({
  String style = 'legacy',
  bool supported = true,
}) => InterfaceStyleController(
  supportsModern: supported,
  savedStyle: style,
  writeStyle: (_) async {},
);

void main() {
  testWidgets('home calendar entry selects its destination and returns home', (
    tester,
  ) async {
    await _mount(tester, _controller(style: 'modern'), preview: true);
    await tester.tap(find.byKey(const ValueKey('home-calendar')));
    await tester.pumpAndSettle();
    expect(find.text('modern-timeline'), findsOneWidget);
    final selected = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(selected.selectedIndex, 1);
    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();
    expect(find.byType(ModernHomeView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching replaces page state, retains shared data, and supports both return directions',
    (tester) async {
      final controller = _controller();
      await _mount(tester, controller);
      expect(find.text('legacy-popular'), findsOneWidget);
      await tester.tap(find.text('local=0'));
      await tester.pumpAndSettle();
      expect(find.text('local=1'), findsOneWidget);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('legacy-my'), findsOneWidget);
      await controller.setStyle(InterfaceStyle.modern);
      await tester.pumpAndSettle();
      expect(find.text('modern-my'), findsOneWidget);
      expect(find.text('legacy-my'), findsNothing);
      expect(find.text('shared=7'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('modern-popular'), findsOneWidget);
      expect(find.text('local=0'), findsOneWidget);
      await controller.setStyle(InterfaceStyle.legacy);
      await tester.pumpAndSettle();
      expect(find.text('legacy-popular'), findsOneWidget);
      expect(find.text('shared=7'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the real selector returns to the same tab and clears the settings overlay',
    (tester) async {
      await _mount(tester, _controller());
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-style'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('页面样式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新版界面（预览）'));
      await tester.pumpAndSettle();
      expect(find.text('modern-my'), findsOneWidget);
      expect(find.byType(InterfaceStyleTile), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('modern-popular'), findsOneWidget);
      expect(find.byType(InterfaceStyleTile), findsNothing);
      await tester.tap(find.text('open-style'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('页面样式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('旧版界面'));
      await tester.pumpAndSettle();
      expect(find.text('legacy-popular'), findsOneWidget);
      expect(find.byType(InterfaceStyleTile), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a stored modern choice cannot enable the new shell on unsupported platforms',
    (tester) async {
      await _mount(tester, _controller(style: 'modern', supported: false));
      expect(find.text('legacy-popular'), findsOneWidget);
      expect(find.byKey(const ValueKey('modern-navigation')), findsNothing);
    },
  );

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    for (final style in ['legacy', 'modern']) {
      testWidgets('$style shell renders at $size with enlarged text', (
        tester,
      ) async {
        await _mount(
          tester,
          _controller(style: style),
          size: size,
          textScale: 1.6,
        );
        expect(find.text('$style-popular'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'renders the modern Android home inside the actual navigation shell',
    (tester) async {
      // Widget 测试默认使用占位字体，预览需显式加载项目中文字体和图标。
      await tester.runAsync(() async {
        final textFont = FontLoader('MI_Sans_Regular')
          ..addFont(rootBundle.load('assets/fonts/MiSans-Regular.ttf'));
        final iconFont = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        final lucideFont = FontLoader('packages/lucide_icons_flutter/Lucide')
          ..addFont(
            rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
          );
        await Future.wait([
          textFont.load(),
          iconFont.load(),
          lucideFont.load(),
        ]);
      });
      await _mount(tester, _controller(style: 'modern'), preview: true);
      expect(find.byTooltip('Kazumi'), findsNothing);
      expect(find.byKey(const ValueKey('home-calendar')), findsOneWidget);
      expect(find.text('搜索番剧、角色或关键词'), findsOneWidget);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('preview-boundary')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final screenshot = File(
          'docs/verification/android-modern-home-channels-widget.png',
        );
        await screenshot.parent.create(recursive: true);
        await screenshot.writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    },
  );
}
