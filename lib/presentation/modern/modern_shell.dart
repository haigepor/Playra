import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'home/home_theme.dart';
import 'widgets/liquid_glass_navigation.dart';
import 'widgets/native_liquid_navigation.dart';

class ModernShell extends StatefulWidget {
  const ModernShell({
    super.key,
    required this.selectedIndex,
    required this.selectDestination,
    required this.outlet,
  });
  final int selectedIndex;
  final ValueChanged<int> selectDestination;
  final Widget outlet;

  static const destinations = [
    NavigationDestination(icon: Icon(LucideIcons.compass), label: '发现'),
    NavigationDestination(icon: Icon(LucideIcons.calendarDays), label: '日历'),
    NavigationDestination(icon: Icon(LucideIcons.bookmark), label: '追番'),
    NavigationDestination(icon: Icon(LucideIcons.userRound), label: '我的'),
  ];

  @override
  State<ModernShell> createState() => _ModernShellState();
}

class _ModernShellState extends State<ModernShell> {
  final _backdrop = LiquidGlassBackdropController();
  late final _native = NativeLiquidNavigationController(
    onSelected: (index) => widget.selectDestination(index),
  );

  @override
  void initState() {
    super.initState();
    _native.addListener(_nativeChanged);
    _native.initialize();
  }

  void _nativeChanged() {
    if (!mounted) return;
    _backdrop.setNativeSourceFrame(
      _native.supported ? _native.invalidateBackdrop : null,
    );
    setState(() {});
  }

  @override
  void dispose() {
    _native.removeListener(_nativeChanged);
    _native.dispose();
    _backdrop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = modernHomeTheme(Theme.of(context), forceDark: true);
    return Scaffold(
      extendBody: true,
      body: LiquidGlassBackdrop(controller: _backdrop, child: widget.outlet),
      bottomNavigationBar: Theme(
        data: theme,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SafeArea(
            top: false,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _native.supported
                    ? NativeLiquidNavigationBar(
                        controller: _native,
                        selectedIndex: widget.selectedIndex,
                        destinations: ModernShell.destinations,
                      )
                    : LiquidGlassNavigationBar(
                        backdrop: _backdrop,
                        selectedIndex: widget.selectedIndex,
                        onDestinationSelected: widget.selectDestination,
                        destinations: ModernShell.destinations,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
