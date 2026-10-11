import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/index_page.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/presentation/interface_page_host.dart';
import 'package:kazumi/presentation/interface_style.dart';

class _Fixture {
  final created = <int>[];
  final visibility = <int, bool>{};
  final scroll = <int, ScrollController>{};
  late final builders = List<WidgetBuilder>.generate(
    4,
    (index) =>
        (_) => _Page(index: index, fixture: this),
  );
}

class _Page extends StatefulWidget {
  const _Page({required this.index, required this.fixture});
  final int index;
  final _Fixture fixture;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  int count = 0;
  final scroll = ScrollController();
  final input = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.fixture.created.add(widget.index);
    widget.fixture.scroll[widget.index] = scroll;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.fixture.visibility[widget.index] = !RouteVisibility.isCoveredOf(
      context,
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    key: ValueKey('page-${widget.index}'),
    children: [
      TextButton(
        onPressed: () => setState(() => count++),
        child: Text('计数-${widget.index}:$count'),
      ),
      TextField(key: ValueKey('input-${widget.index}'), controller: input),
      TextButton(
        onPressed: () => context.pushNamed('/settings/mock'),
        child: const Text('打开设置'),
      ),
      Expanded(
        child: ListView.builder(
          key: ValueKey('scroll-${widget.index}'),
          controller: scroll,
          itemCount: 80,
          itemExtent: 60,
          itemBuilder: (_, index) => Text('条目-$index'),
        ),
      ),
    ],
  );
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
  bool modern = true,
  bool reduceMotion = false,
  String initialRoute = '/tab/popular/',
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fixture = _Fixture();
  final paths = ['popular', 'timeline', 'collect', 'my'];
  final module = createModule(
    register: (root) {
      root.module(
        createModule(
          path: '/tab',
          register: (tabs) {
            tabs.route(
              '/',
              transition: TransitionType.none,
              child: (_, state) => IndexPage(
                location: state.uri.path,
                mobilePageBuilders: fixture.builders,
              ),
              children: (sub) {
                for (var i = 0; i < paths.length; i++) {
                  final index = i;
                  sub.route(
                    '/${paths[i]}/',
                    transition: TransitionType.none,
                    child: (_, _) => InterfacePageHost(
                      legacy: fixture.builders[index],
                      modern: fixture.builders[index],
                    ),
                  );
                }
              },
            );
          },
        ),
      );
      root.route(
        '/settings/mock',
        transition: TransitionType.none,
        child: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.pop(),
            child: const Text('返回设置'),
          ),
        ),
      );
    },
  );
  await tester.pumpWidget(
    ModularApp(
      module: module,
      initialRoute: initialRoute,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [rootRouteObserver],
      provide: (scoped) => scoped.addChangeNotifier<InterfaceStyleController>(
        () => InterfaceStyleController(
          supportsModern: true,
          savedStyle: modern ? 'modern' : 'legacy',
          writeStyle: (_) async {},
        ),
      ),
      child: Builder(
        builder: (context) => MaterialApp.router(
          routerConfig: ModularApp.routerConfigOf(context),
          theme: ThemeData(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

void main() {
  testWidgets('移动端横移、URL 同步且跨页不加载中间页', (tester) async {
    final fixture = await _mount(tester);
    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final target = tester.getTopLeft(find.byKey(const ValueKey('page-3')));
    expect(target.dx, greaterThan(0));
    expect(target.dx, lessThan(390));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('page-0'))).dx,
      lessThan(0),
    );
    expect(fixture.created, [0, 3]);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('page-3'))).dx, 0);
    final context = tester.element(find.byKey(const ValueKey('page-3')));
    expect(context.routeState().uri.path, '/tab/my/');
    expect(fixture.visibility[0], isFalse);
    expect(fixture.visibility[3], isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('往返保留计数、搜索输入和滚动位置', (tester) async {
    final fixture = await _mount(tester);
    await tester.tap(find.text('计数-0:0'));
    await tester.enterText(find.byKey(const ValueKey('input-0')), '测试搜索');
    await tester.drag(
      find.byKey(const ValueKey('scroll-0')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final offset = fixture.scroll[0]!.offset;
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();
    expect(find.text('计数-0:1'), findsOneWidget);
    expect(find.text('测试搜索'), findsOneWidget);
    expect(fixture.scroll[0]!.offset, offset);
    expect(fixture.created, [0, 3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('快速反向切换最终落在最后选择，重复点击不重建', (tester) async {
    final fixture = await _mount(tester);
    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 65));
    await tester.tap(find.text('日历'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 35));
    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('page-0'))).dx, 0);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(fixture.created.where((index) => index == 0), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置覆盖和返回保留页面，系统返回到发现', (tester) async {
    final fixture = await _mount(tester, initialRoute: '/tab/my/');
    await tester.tap(find.text('计数-3:0'));
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    expect(fixture.visibility[3], isFalse);
    await tester.tap(find.text('返回设置'));
    await tester.pumpAndSettle();
    expect(find.text('计数-3:1'), findsOneWidget);
    expect(fixture.visibility[3], isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('计数-0:0'), findsOneWidget);
    expect(fixture.visibility[3], isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [
    (TargetPlatform.windows, true),
    (TargetPlatform.android, false),
  ]) {
    testWidgets('桌面或旧版保持原切换方式 $mode', (tester) async {
      final fixture = await _mount(tester, platform: mode.$1, modern: mode.$2);
      await tester.tap(find.text('计数-0:0'));
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(mode.$2 ? '发现' : '推荐'));
      await tester.pumpAndSettle();
      expect(find.text('计数-0:0'), findsOneWidget);
      expect(fixture.created.where((index) => index == 0), hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('减少动画时直接到目标页，手指滑动不劫持主 Tab', (tester) async {
    await _mount(tester, reduceMotion: true);
    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey('page-3'))).dx, 0);
    await tester.drag(
      find.byKey(const ValueKey('page-3')),
      const Offset(-230, 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动端新旧样式来回切换保持当前 Tab，安全区不随内容移动', (tester) async {
    await _mount(tester);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byKey(const ValueKey('page-3')));
    final style = context.read<InterfaceStyleController>();
    await style.setStyle(InterfaceStyle.legacy);
    await tester.pumpAndSettle();
    expect(find.text('计数-3:0'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    await style.setStyle(InterfaceStyle.modern);
    await tester.pumpAndSettle();
    expect(find.text('计数-3:0'), findsOneWidget);
    final barPosition = tester.getTopLeft(find.byType(NavigationBar));
    await tester.tap(find.text('日历'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getTopLeft(find.byType(NavigationBar)), barPosition);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
