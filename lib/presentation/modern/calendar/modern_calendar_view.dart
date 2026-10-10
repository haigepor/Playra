import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/services/calendar/calendar_models.dart';
import '../home/home_theme.dart';
import 'modern_calendar_controller.dart';
import 'widgets/calendar_poster_card.dart';
import 'widgets/calendar_season_picker.dart';

class ModernCalendarView extends StatefulWidget {
  const ModernCalendarView({
    super.key,
    required this.controller,
    required this.onDetails,
    required this.onResume,
    required this.onStyle,
  });
  final ModernCalendarController controller;
  final ValueChanged<BangumiItem> onDetails;
  final ValueChanged<History> onResume;
  final VoidCallback onStyle;
  @override
  State<ModernCalendarView> createState() => _ModernCalendarViewState();
}

class _ModernCalendarViewState extends State<ModernCalendarView> {
  late final PageController _pages;
  late int _day;
  bool _pageAnimating = false;
  int _pageAnimationVersion = 0;
  final _weekScroll = ScrollController();
  int? _revealedDay;
  double? _revealedWidth;

  @override
  void initState() {
    super.initState();
    _day = widget.controller.weekday;
    _pages = PageController(initialPage: _day - 1);
    widget.controller.addListener(_syncDay);
  }

  void _syncDay() {
    final day = widget.controller.weekday;
    if (_day == day) return;
    _day = day;
    final version = ++_pageAnimationVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pages.hasClients || version != _pageAnimationVersion) {
        return;
      }
      _pageAnimating = true;
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260);
      unawaited(
        _pages
            .animateToPage(
              day - 1,
              duration: duration,
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
              if (mounted && version == _pageAnimationVersion) {
                _pageAnimating = false;
              }
            }),
      );
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncDay);
    _pages.dispose();
    _weekScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    child: Builder(
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: colors.surface,
          ),
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) {
                      final controller = widget.controller;
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 6, 12, 0),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '放送日历',
                                    style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                ShadButton.ghost(
                                  key: const ValueKey('calendar-season'),
                                  size: ShadButtonSize.sm,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  onPressed: () => _showSeason(context),
                                  trailing: const Icon(
                                    LucideIcons.chevronDown,
                                    size: 14,
                                  ),
                                  child: Text(
                                    controller.seasonLabel,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _weekSelector(context),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
                            child: Row(
                              children: [
                                _filterButton(
                                  context,
                                  '全部',
                                  !controller.watchingOnly,
                                  () => controller.setFilters(
                                    watchingOnly: false,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _filterButton(
                                  context,
                                  '仅追番',
                                  controller.watchingOnly,
                                  () =>
                                      controller.setFilters(watchingOnly: true),
                                ),
                                const Spacer(),
                                if (!controller.isToday)
                                  TextButton(
                                    onPressed: controller.goToday,
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                      ),
                                    ),
                                    child: const Text(
                                      '今天',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                IconButton(
                                  key: const ValueKey('calendar-filters'),
                                  tooltip: '筛选与排序',
                                  onPressed: () => _showFilters(context),
                                  icon: Badge(
                                    isLabelVisible: controller.hasFilters,
                                    smallSize: 5,
                                    child: Icon(
                                      LucideIcons.slidersHorizontal,
                                      size: 19,
                                      color: controller.hasFilters
                                          ? colors.primary
                                          : colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (controller.loading && controller.snapshot != null)
                            const LinearProgressIndicator(minHeight: 2),
                          Expanded(
                            child: ScrollConfiguration(
                              behavior: const MaterialScrollBehavior().copyWith(
                                dragDevices: {
                                  PointerDeviceKind.touch,
                                  PointerDeviceKind.mouse,
                                  PointerDeviceKind.trackpad,
                                },
                              ),
                              child: PageView.builder(
                                key: const ValueKey('calendar-days'),
                                controller: _pages,
                                itemCount: 7,
                                onPageChanged: (index) {
                                  if (_pageAnimating) return;
                                  _day = index + 1;
                                  controller.selectWeekday(index + 1);
                                },
                                itemBuilder: (context, index) =>
                                    _dayList(context, index + 1),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _weekSelector(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final controller = widget.controller;
      final colors = Theme.of(context).colorScheme;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final width = (bounds.maxWidth / 7).clamp(44.0 * scale, double.infinity);
      if (_revealedDay != controller.weekday || _revealedWidth != width) {
        final initial = _revealedDay == null;
        _revealedDay = controller.weekday;
        _revealedWidth = width;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_weekScroll.hasClients) return;
          final offset =
              ((controller.weekday - 1) * width -
                      bounds.maxWidth / 2 +
                      width / 2)
                  .clamp(0.0, _weekScroll.position.maxScrollExtent);
          if (initial || MediaQuery.disableAnimationsOf(context)) {
            _weekScroll.jumpTo(offset);
          } else {
            unawaited(
              _weekScroll.animateTo(
                offset,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
              ),
            );
          }
        });
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _weekScroll,
        child: SizedBox(
          width: width * 7,
          height: 50 + 12 * (scale - 1).clamp(0, 3),
          child: Stack(
            children: [
              Row(
                children: [
                  for (var day = 1; day <= 7; day++)
                    SizedBox(
                      width: width,
                      child: Semantics(
                        selected: controller.weekday == day,
                        child: TextButton(
                          key: ValueKey('calendar-weekday-$day'),
                          onPressed: () {
                            controller.selectWeekday(day);
                            if (_weekScroll.hasClients) {
                              _weekScroll.animateTo(
                                ((day - 1) * width -
                                        bounds.maxWidth / 2 +
                                        width / 2)
                                    .clamp(
                                      0.0,
                                      _weekScroll.position.maxScrollExtent,
                                    ),
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: controller.weekday == day
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                            overlayColor: Colors.transparent,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '周${'一二三四五六日'[day - 1]}',
                                style: TextStyle(
                                  fontSize: controller.weekday == day ? 15 : 13,
                                  fontWeight: controller.weekday == day
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                controller.currentSeason &&
                                        controller.today == day
                                    ? '今天'
                                    : '${controller.dayEntries(day).length}部',
                                style: TextStyle(
                                  fontSize: 9,
                                  color:
                                      controller.currentSeason &&
                                          controller.today == day
                                      ? colors.primary
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 4,
                child: AnimatedBuilder(
                  animation: _pages,
                  builder: (context, _) {
                    final page =
                        _pages.hasClients &&
                            _pages.position.hasContentDimensions
                        ? _pages.page ?? controller.weekday - 1.0
                        : controller.weekday - 1.0;
                    return Stack(
                      children: [
                        Positioned(
                          left: width * page + (width - 22) / 2,
                          top: 0,
                          child: Container(
                            width: 22,
                            height: 3,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _filterButton(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback? onTap,
  ) {
    final colors = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(56, 36),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: selected
            ? colors.surfaceContainerHighest
            : Colors.transparent,
        foregroundColor: selected ? colors.primary : colors.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _dayList(BuildContext context, int day) {
    final controller = widget.controller;
    final items = controller.dayEntries(day);
    final mine = items
        .where(
          (e) => controller.collectionFor(e.item.id) == CollectType.watching,
        )
        .toList();
    final others = items
        .where(
          (e) => controller.collectionFor(e.item.id) != CollectType.watching,
        )
        .toList();
    final pending = controller.pendingEntries;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: CustomScrollView(
        key: PageStorageKey('modern-calendar-${controller.season}-$day'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '周${'一二三四五六日'[day - 1]}放送',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${items.length}部',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (controller.error != null || controller.snapshot?.notice != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.error ?? controller.snapshot!.notice!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (controller.error != null)
                      TextButton(
                        onPressed: controller.refresh,
                        child: const Text('重试'),
                      ),
                  ],
                ),
              ),
            ),
          if (controller.loading && controller.snapshot == null)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.list(
                children: [
                  for (var i = 0; i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        height: 126,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (!controller.loading && items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 28,
                ),
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.calendarDays,
                      size: 30,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      controller.error != null && controller.snapshot == null
                          ? '暂时无法加载'
                          : controller.hasFilters
                          ? '没有符合筛选的番剧'
                          : '这一天暂无放送',
                    ),
                    if (controller.hasFilters)
                      TextButton(
                        onPressed: controller.clearFilters,
                        child: const Text('清除筛选'),
                      ),
                  ],
                ),
              ),
            ),
          ..._section(context, mine, controller.watchingOnly ? null : '我的追番'),
          ..._section(context, others, mine.isEmpty ? null : '其他放送'),
          ..._section(context, pending, '排期待定'),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    List<ScheduleEntry> entries,
    String? title,
  ) {
    if (entries.isEmpty) return [];
    final controller = widget.controller;
    return [
      if (title != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 13,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${entries.length}部',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final history = controller.historyFor(entry.item.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CalendarPosterCard(
                key: ValueKey(
                  'calendar-card-${entry.weekday}-${entry.item.id}',
                ),
                entry: entry,
                collection: controller.collectionFor(entry.item.id),
                history: history,
                onVisible: () => controller.queueDetail(entry),
                onDetails: () => widget.onDetails(entry.item),
                onResume: history == null
                    ? null
                    : () => widget.onResume(history),
              ),
            );
          },
        ),
      ),
    ];
  }

  Future<void> _showFilters(BuildContext context) =>
      _sheet(context, '筛选与排序', (context) {
        final controller = widget.controller;
        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '地区',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final option in [
                    (ScheduleRegion.all, '全部'),
                    (ScheduleRegion.japanese, '日漫'),
                    (ScheduleRegion.chinese, '国漫'),
                  ])
                    _filterButton(
                      context,
                      option.$2,
                      controller.region == option.$1,
                      () => controller.setFilters(region: option.$1),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '排序',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final option in [
                    (CalendarSort.schedule, '放送时间'),
                    (CalendarSort.popularity, '热度'),
                    (CalendarSort.rating, '评分'),
                  ])
                    _filterButton(
                      context,
                      option.$2,
                      controller.sort == option.$1,
                      () => controller.setFilters(sort: option.$1),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('隐藏看过', style: TextStyle(fontSize: 14)),
                value: controller.hideWatched,
                onChanged: (value) => controller.setFilters(hideWatched: value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('隐藏抛弃', style: TextStyle(fontSize: 14)),
                value: controller.hideAbandoned,
                onChanged: (value) =>
                    controller.setFilters(hideAbandoned: value),
              ),
              const SizedBox(height: 10),
              ShadButton.outline(
                onPressed: controller.clearFilters,
                child: const Text('重置筛选'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onStyle();
                },
                child: const Text('切换新旧页面样式', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
      });

  Future<void> _showSeason(BuildContext context) {
    return _sheet(
      context,
      null,
      (context) => CalendarSeasonPicker(
        selectedSeason: widget.controller.season,
        now: DateTime.now(),
        onClose: () => Navigator.of(context).pop(),
        onSelected: (season) {
          Navigator.of(context).pop();
          unawaited(widget.controller.selectSeason(season));
        },
      ),
      maxWidth: 460,
      expandContent: true,
    );
  }

  Future<void> _sheet(
    BuildContext context,
    String? title,
    Widget Function(BuildContext) content, {
    double? maxWidth,
    bool expandContent = false,
  }) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    showDragHandle: true,
    constraints: maxWidth == null ? null : BoxConstraints(maxWidth: maxWidth),
    builder: (_) => ModernHomeScope(
      child: Builder(
        builder: (context) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.sizeOf(context).height *
                      (expandContent ? .84 : .8) -
                  (expandContent
                      ? MediaQuery.viewPaddingOf(context).bottom
                      : 0),
            ),
            child: expandContent
                ? SizedBox(
                    height: 600,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: content(context),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '关闭',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: Icon(
                                  LucideIcons.x,
                                  size: 20,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        content(context),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
}
