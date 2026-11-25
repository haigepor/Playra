import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_segmented_tab_bar.dart';

/// Fixed top-level discovery channels shown in the home header.
enum HomeChannelId { recommend, hot, anime, drama, movie, variety }

class HomeChannel {
  const HomeChannel({required this.id, required this.label});

  final HomeChannelId id;
  final String label;
}

const List<HomeChannel> kHomeChannels = <HomeChannel>[
  HomeChannel(id: HomeChannelId.recommend, label: '推荐'),
  HomeChannel(id: HomeChannelId.hot, label: '热门'),
  HomeChannel(id: HomeChannelId.anime, label: '动漫'),
  HomeChannel(id: HomeChannelId.drama, label: '电视剧'),
  HomeChannel(id: HomeChannelId.movie, label: '电影'),
  HomeChannel(id: HomeChannelId.variety, label: '综艺'),
];

/// Header above the discovery feed.
///
/// Phones use a brand row above an edge-to-edge sliding channel bar; tablets
/// keep the shell rail for identity and place channels and actions in a single
/// responsive toolbar above a full-width divider.
class HomeTopBar extends StatefulWidget {
  const HomeTopBar({
    super.key,
    required this.layout,
    required this.onSearch,
    required this.onCalendar,
    this.tabController,
    this.channels = kHomeChannels,
    this.initialIndex = 0,
    this.onChannelSelected,
    this.onHistory,
    this.sourceLabel = '',
  });

  final HomeLayoutMetrics layout;
  final TabController? tabController;
  final List<HomeChannel> channels;
  final int initialIndex;
  final ValueChanged<int>? onChannelSelected;
  final VoidCallback onSearch;
  final VoidCallback onCalendar;
  final VoidCallback? onHistory;
  final String sourceLabel;

  @override
  State<HomeTopBar> createState() => _HomeTopBarState();
}

class _HomeTopBarState extends State<HomeTopBar>
    with SingleTickerProviderStateMixin {
  TabController? _internalController;

  TabController get _controller =>
      widget.tabController ?? (_internalController ??= _createController());

  TabController _createController() {
    final safeIndex = widget.channels.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.channels.length - 1);
    return TabController(
      length: widget.channels.length,
      initialIndex: safeIndex,
      vsync: this,
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.tabController == null) {
      _internalController = _createController();
    }
  }

  @override
  void didUpdateWidget(covariant HomeTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabController != null && _internalController != null) {
      _internalController!.dispose();
      _internalController = null;
    } else if (widget.tabController == null &&
        (_internalController == null ||
            _internalController!.length != widget.channels.length)) {
      _internalController?.dispose();
      _internalController = _createController();
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.layout.isPhone ? _buildPhone(context) : _buildTablet(context);
  }

  Widget _buildPhone(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final gutter = widget.layout.gutter;
    final brandRowHeight = (MediaQuery.textScalerOf(context).scale(20) * 1.15)
        .clamp(40.0, double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 0),
          child: SizedBox(
            height: brandRowHeight,
            child: Row(
              children: [
                const Expanded(child: _HomeBrand()),
                _HomeHeaderIcon(
                  tooltip: '搜索',
                  icon: Icons.search_rounded,
                  color: t.textPrimary,
                  onTap: widget.onSearch,
                ),
                const SizedBox(width: PlayraSpace.sm),
                _HomeHeaderIcon(
                  tooltip: '历史记录',
                  icon: Icons.history_rounded,
                  color: t.textPrimary,
                  onTap: widget.onHistory,
                ),
              ],
            ),
          ),
        ),
        _buildChannelTabs(context, horizontalPadding: gutter - 10),
        Divider(
          height: 1,
          thickness: 1,
          color: t.divider.withValues(alpha: .6),
        ),
      ],
    );
  }

  Widget _buildTablet(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final gutter = widget.layout.gutter;
    final landscape = widget.layout.isTabletLandscape;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.layout.contentMaxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 6, gutter, 6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                  final searchWidth =
                      ((constraints.maxWidth * (landscape ? .28 : .30)) /
                              textScale)
                          .clamp(200.0, landscape ? 400.0 : 280.0);
                  final compactSearch = constraints.maxWidth < 680;
                  return Row(
                    children: [
                      Expanded(
                        child: _buildChannelTabs(context, horizontalPadding: 0),
                      ),
                      const SizedBox(width: PlayraSpace.sm),
                      if (compactSearch)
                        _HomeHeaderIcon(
                          tooltip: '搜索',
                          icon: Icons.search_rounded,
                          color: t.textPrimary,
                          onTap: widget.onSearch,
                        )
                      else
                        SizedBox(
                          width: searchWidth,
                          child: _HomeSearchEntry(
                            hint: '搜索你感兴趣的内容…',
                            height: 38,
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
                      const SizedBox(width: PlayraSpace.sm),
                      _HomeHeaderIcon(
                        tooltip: '历史记录',
                        icon: Icons.history_rounded,
                        color: t.textPrimary,
                        onTap: widget.onHistory,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: t.divider.withValues(alpha: .6),
        ),
      ],
    );
  }

  Widget _buildChannelTabs(
    BuildContext context, {
    required double horizontalPadding,
  }) {
    return PlayraUnderlineTabBar(
      labels: [for (final channel in widget.channels) channel.label],
      controller: _controller,
      horizontalPadding: horizontalPadding < 0 ? 0 : horizontalPadding,
      onTap: widget.onChannelSelected,
    );
  }
}

class _HomeBrand extends StatelessWidget {
  const _HomeBrand();

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/images/logo/playra_header_mark.svg',
          width: 24,
          height: 24,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            'Playra',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
              height: 1.0,
            ),
          ),
        ),
      ],
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
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 36,
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}
