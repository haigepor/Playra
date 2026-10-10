import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'component_catalog.dart';

/// 组件实验室拥有独立导航和主题，退出后恢复宿主页面。
class ShadcnGallery extends StatefulWidget {
  const ShadcnGallery({super.key, this.onExit});
  final VoidCallback? onExit;

  @override
  State<ShadcnGallery> createState() => _ShadcnGalleryState();
}

class _ShadcnGalleryState extends State<ShadcnGallery> {
  final navigator = GlobalKey<NavigatorState>();
  ThemeMode mode = ThemeMode.light;
  bool hasHistory = false;
  late final observer = _GalleryNavigationObserver(() {
    // 内部 MaterialApp 会消费导航通知，显式同步返回状态给宿主路由。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = navigator.currentState?.canPop() ?? false;
      if (next != hasHistory) setState(() => hasHistory = next);
    });
  });

  ShadThemeData theme(Brightness brightness) => ShadThemeData(
    brightness: brightness,
    colorScheme: brightness == Brightness.dark
        ? const ShadZincColorScheme.dark()
        : const ShadZincColorScheme.light(),
    textTheme: ShadTextTheme(
      family: 'MI_Sans_Regular',
      custom: {
        'myCustomStyle': TextStyle(
          fontSize: 16,
          color: brightness == Brightness.dark ? Colors.green : Colors.blue,
        ),
      },
    ),
  );

  @override
  Widget build(BuildContext context) => GalleryControls(
    dark: mode == ThemeMode.dark,
    toggleTheme: () => setState(
      () => mode = mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
    ),
    onExit: widget.onExit,
    child: PopScope<Object?>(
      canPop: !hasHistory,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) navigator.currentState!.pop(result);
      },
      child: ShadApp.custom(
        themeMode: mode,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        appBuilder: (context) => MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [observer],
          debugShowCheckedModeBanner: false,
          theme: Theme.of(context),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalShadLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          routes: shadcnDemoRoutes,
          home: const _CatalogIndex(),
          builder: (context, child) => ShadAppBuilder(child: child!),
        ),
      ),
    ),
  );
}

class _GalleryNavigationObserver extends NavigatorObserver {
  _GalleryNavigationObserver(this.onChange);
  final VoidCallback onChange;

  @override
  void didChangeTop(
    Route<dynamic> topRoute,
    Route<dynamic>? previousTopRoute,
  ) => onChange();
}

class GalleryControls extends InheritedWidget {
  const GalleryControls({
    super.key,
    required super.child,
    required this.dark,
    required this.toggleTheme,
    this.onExit,
  });
  final bool dark;
  final VoidCallback toggleTheme;
  final VoidCallback? onExit;
  static GalleryControls of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GalleryControls>()!;

  @override
  bool updateShouldNotify(GalleryControls oldWidget) =>
      dark != oldWidget.dark || onExit != oldWidget.onExit;
}

String componentName(String route) => route == '/divider'
    ? 'Separator'
    : route
          .substring(1)
          .split('-')
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');

class _CatalogIndex extends StatefulWidget {
  const _CatalogIndex();
  @override
  State<_CatalogIndex> createState() => _CatalogIndexState();
}

class _CatalogIndexState extends State<_CatalogIndex> {
  final searchController = TextEditingController();
  String query = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controls = GalleryControls.of(context);
    final routes = shadcnDemoRoutes.keys
        .where(
          (route) =>
              componentName(route).toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('组件实验室'),
        leading: controls.onExit == null
            ? null
            : IconButton(
                tooltip: '关闭组件实验室',
                icon: const Icon(Icons.close),
                onPressed: controls.onExit,
              ),
        actions: [
          IconButton(
            tooltip: '切换明暗主题',
            icon: Icon(controls.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: controls.toggleTheme,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'shadcn_ui 0.57.1 · ${shadcnDemoRoutes.length} 个官方示例页',
                      ),
                      const SizedBox(height: 12),
                      ShadInput(
                        controller: searchController,
                        placeholder: const Text('搜索组件，例如 Button、Input'),
                        onChanged: (value) => setState(() => query = value),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: routes.isEmpty
                      ? const Center(child: Text('没有匹配的组件'))
                      : ListView.separated(
                          itemCount: routes.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) => ListTile(
                            title: Text(componentName(routes[index])),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                Navigator.of(context).pushNamed(routes[index]),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
