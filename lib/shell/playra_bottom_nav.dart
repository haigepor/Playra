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
    final t = PlayraTokens.of(context);
    return Material(
      color: t.surface,
      shape: Border(top: BorderSide(color: t.borderSubtle)),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: Semantics(
                  selected: i == selectedIndex,
                  button: true,
                  child: InkWell(
                    onTap: () => onSelected(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            i == selectedIndex
                                ? destinations[i].selectedIcon
                                : destinations[i].icon,
                            size: 24,
                            color: i == selectedIndex
                                ? t.primary
                                : t.foregroundSubtle,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            destinations[i].label,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.2,
                              fontWeight: i == selectedIndex
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i == selectedIndex
                                  ? t.primary
                                  : t.foregroundSubtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
