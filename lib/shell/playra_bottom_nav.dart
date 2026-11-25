import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';

/// One destination in the phone bottom dock.
class PlayraNavDestination {
  const PlayraNavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Floating frosted-glass capsule bottom dock (Option B) with a smooth sliding
/// lavender pill indicator and zero Material hover/splash gray rectangles.
class PlayraBottomNav extends StatelessWidget {
  const PlayraBottomNav({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<PlayraNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (destinations.isEmpty) return const SizedBox.shrink();
    final t = PlayraTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaler = MediaQuery.textScalerOf(context);
    final reduceMotion = PlayraMotion.reduceOf(context);
    final labelHeight = scaler.scale(11) * 1.2;
    final pillHeight = math.max(50.0, 22.0 + 3.0 + labelHeight + 12.0);
    final safeSelected = selectedIndex.clamp(0, destinations.length - 1);

    final dockBg = isDark
        ? const Color(0xD8141621)
        : Colors.white.withValues(alpha: 0.88);
    final dockBorder = isDark
        ? Colors.white.withValues(alpha: 0.11)
        : t.border;
    final capsuleGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              t.primary.withValues(alpha: 0.22),
              t.primary.withValues(alpha: 0.12),
            ]
          : [
              t.primary.withValues(alpha: 0.16),
              t.primary.withValues(alpha: 0.09),
            ],
    );

    final fadeBase = isDark
        ? const Color(0xFF0E1017)
        : Theme.of(context).scaffoldBackgroundColor;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.42, 1.0],
          colors: [
            fadeBase.withValues(alpha: 0.0),
            fadeBase.withValues(alpha: isDark ? 0.78 : 0.80),
            fadeBase.withValues(alpha: isDark ? 0.98 : 0.98),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.46 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: dockBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: dockBorder, width: 1),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth =
                        constraints.maxWidth / destinations.length;
                    return SizedBox(
                      height: pillHeight,
                      child: Stack(
                        children: [
                          AnimatedPositioned(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            left: safeSelected * itemWidth,
                            top: 0,
                            bottom: 0,
                            width: itemWidth,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: capsuleGradient,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: t.primary.withValues(
                                      alpha: isDark ? 0.26 : 0.18,
                                    ),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (var i = 0; i < destinations.length; i++)
                                Expanded(
                                  child: _DockItem(
                                    destination: destinations[i],
                                    selected: i == safeSelected,
                                    activeColor: t.primary,
                                    inactiveColor: t.foregroundSubtle,
                                    onTap: () => onSelected(i),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.destination,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final PlayraNavDestination destination;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    return Semantics(
      selected: selected,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 21,
                  color: color,
                ),
                const SizedBox(height: 3),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
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
