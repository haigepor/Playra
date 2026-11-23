import 'package:flutter/material.dart';

import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';

/// Header above the discovery feed.
///
/// Phones get three rows (brand, full-width search, categories); tablets keep
/// the compact single-row toolbar because the side rail already provides the
/// product identity.
class HomeTopBar extends StatefulWidget {
  const HomeTopBar({
    super.key,
    required this.layout,
    required this.categories,
    required this.onSearch,
    required this.onCategorySelected,
    required this.onCalendar,
    this.onHistory,
    this.sourceLabel = '',
  });

  final HomeLayoutMetrics layout;
  final Future<List<MediaCategory>>? categories;
  final VoidCallback onSearch;
  final ValueChanged<MediaCategory> onCategorySelected;
  final VoidCallback onCalendar;
  final VoidCallback? onHistory;
  final String sourceLabel;

  @override
  State<HomeTopBar> createState() => _HomeTopBarState();
}

class _HomeTopBarState extends State<HomeTopBar> {
  String? _selectedId = '';

  @override
  Widget build(BuildContext context) {
    return widget.layout.isPhone ? _buildPhone(context) : _buildTablet(context);
  }

  Widget _buildPhone(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final gutter = widget.layout.gutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        widget.layout.headerTopPadding,
        gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: (MediaQuery.textScalerOf(context).scale(26) * 1.1).clamp(
              56,
              double.infinity,
            ),
            child: Row(
              children: [
                Text(
                  'Playra',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    letterSpacing: -1,
                    height: 1.0,
                  ),
                ),
                const Spacer(),
                _HomeHeaderIcon(
                  tooltip: '搜索',
                  icon: Icons.search,
                  color: t.textPrimary,
                  onTap: widget.onSearch,
                ),
                const SizedBox(width: PlayraSpace.xs),
                _HomeHeaderIcon(
                  tooltip: '历史记录',
                  icon: Icons.history_rounded,
                  color: t.textPrimary,
                  onTap: widget.onHistory,
                ),
              ],
            ),
          ),
          SizedBox(
            height: (MediaQuery.textScalerOf(context).scale(14) * 1.2 + 20)
                .clamp(48, double.infinity),
            child: _buildCategories(
              context,
              visualHeight: widget.layout.categoryVisualHeight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTablet(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final gutter = widget.layout.gutter;
    final landscape = widget.layout.isTabletLandscape;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        PlayraSpace.sm,
        gutter,
        PlayraSpace.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final searchWidth =
              ((constraints.maxWidth * (landscape ? .30 : .32)) / textScale)
                  .clamp(220.0, landscape ? 440.0 : 300.0);
          return SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(child: _buildCategories(context, visualHeight: 40)),
                const SizedBox(width: PlayraSpace.md),
                SizedBox(
                  width: searchWidth,
                  child: _HomeSearchEntry(
                    hint: '搜索你感兴趣的内容…',
                    height: 44,
                    onTap: widget.onSearch,
                  ),
                ),
                const SizedBox(width: PlayraSpace.sm),
                _HomeHeaderIcon(
                  tooltip: '时间表',
                  icon: Icons.calendar_month_rounded,
                  color: t.textPrimary,
                  onTap: widget.onCalendar,
                ),
                const SizedBox(width: PlayraSpace.xs),
                _HomeHeaderIcon(
                  tooltip: '历史记录',
                  icon: Icons.history_rounded,
                  color: t.textPrimary,
                  onTap: widget.onHistory,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategories(
    BuildContext context, {
    required double visualHeight,
  }) {
    return FutureBuilder<List<MediaCategory>>(
      future: widget.categories,
      builder: (context, snapshot) {
        final categories = snapshot.data ?? const <MediaCategory>[];
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _HomeTab(
                label: '推荐',
                height: visualHeight,
                selected: _selectedId == '',
                onTap: () => setState(() => _selectedId = ''),
              ),
              for (final category in categories) ...[
                const SizedBox(width: PlayraSpace.lg),
                _HomeTab(
                  label: category.name,
                  height: visualHeight,
                  selected: _selectedId == category.id,
                  onTap: () {
                    widget.onCategorySelected(category);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.label,
    required this.height,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double height;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PlayraRadius.overlay),
        child: Container(
          height: (MediaQuery.textScalerOf(context).scale(14) * 1.2 + 20).clamp(
            48,
            double.infinity,
          ),
          constraints: const BoxConstraints(minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? t.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? t.accent : t.textSecondary,
              fontSize: selected ? PlayraType.body : PlayraType.label,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSearchEntry extends StatelessWidget {
  const _HomeSearchEntry({
    required this.hint,
    required this.height,
    required this.onTap,
  });

  final String hint;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return Material(
      color: t.searchFill.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(PlayraRadius.overlay),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PlayraRadius.overlay),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: PlayraSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PlayraRadius.overlay),
            border: Border.all(color: t.divider.withValues(alpha: 0.72)),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 18, color: t.textSecondary),
              const SizedBox(width: PlayraSpace.sm),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: PlayraType.label,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeaderIcon extends StatelessWidget {
  const _HomeHeaderIcon({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    icon: Icon(icon, size: 20, color: color),
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    padding: EdgeInsets.zero,
  );
}
