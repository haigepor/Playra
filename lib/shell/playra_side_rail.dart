import 'package:flutter/material.dart';

import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';

/// Fixed icon rail used by the wide/tablet discovery shell.
///
/// It mirrors the reference app's left navigation: a narrow lavender column,
/// four large tap targets, and a pill behind the selected destination.
class PlayraSideRail extends StatelessWidget {
  const PlayraSideRail({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _destinations = [
    _RailDestination(
      label: '发现',
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore_rounded,
    ),
    _RailDestination(
      label: '日历',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month_rounded,
    ),
    _RailDestination(
      label: '追番',
      icon: Icons.bookmark_outline_rounded,
      selectedIcon: Icons.bookmark_rounded,
    ),
    _RailDestination(
      label: '我的',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: t.railBackground,
        border: Border(right: BorderSide(color: t.divider)),
      ),
      child: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            const SizedBox(height: PlayraSpace.lg),
            _RailBrandMark(),
            const SizedBox(height: PlayraSpace.lg),
            for (var i = 0; i < _destinations.length; i++)
              Expanded(
                child: Center(
                  child: _RailItem(
                    destination: _destinations[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
              ),
            const SizedBox(height: PlayraSpace.lg),
          ],
        ),
      ),
    );
  }
}

class _RailBrandMark extends StatelessWidget {
  const _RailBrandMark();

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: t.railSelected,
            borderRadius: BorderRadius.circular(PlayraRadius.control),
          ),
          child: Icon(Icons.play_arrow_rounded, size: 22, color: t.accent),
        ),
        const SizedBox(height: PlayraSpace.xs),
        Text(
          'Playra',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: PlayraType.micro,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _RailDestination {
  const _RailDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _RailDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final foreground = selected ? t.accent : t.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PlayraRadius.card),
        child: SizedBox(
          width: 56,
          height: 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: PlayraMotion.duration(context, PlayraMotion.state),
                curve: PlayraMotion.curve,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected ? t.railSelected : Colors.transparent,
                  borderRadius: BorderRadius.circular(PlayraRadius.card),
                ),
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 26,
                  color: foreground,
                ),
              ),
              const SizedBox(height: PlayraSpace.xs),
              Text(
                destination.label,
                style: TextStyle(
                  color: foreground,
                  fontSize: PlayraType.small,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
