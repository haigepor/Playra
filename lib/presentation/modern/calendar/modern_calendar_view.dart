import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/widgets/playra_sheet.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../widgets/modern_page_art.dart';
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
      final duration = PlayraMotion.duration(context, PlayraMotion.state);
      if (duration == Duration.zero) {
        _pages.jumpToPage(day - 1);
        _pageAnimating = false;
        return;
      }
      unawaited(
        _pages
            .animateToPage(
              day - 1,
              duration: duration,
              curve: PlayraMotion.curve,
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
              child: ModernPageArt(
                kind: ModernPageArtKind.calendar,
                contentMaxWidth: PlayraLayout.catalogWidth,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: PlayraLayout.catalogWidth,
                    ),
                    child: ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) {
                        final controller = widget.controller;
                        return Column(
                          children: [
                            _header(context, controller),
                            Padding(
                              padding: PlayraLayout.pagePadding(context),
                              child: _weekSelector(context),
                            ),
                            Padding(
                              padding: PlayraLayout.pagePadding(
                                context,
                                top: PlayraSpace.xs,
                              ),
                              child: _toolbar(context, controller),
                            ),
                            Expanded(
                              child: ScrollConfiguration(
                                behavior: const MaterialScrollBehavior()
                                    .copyWith(
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
          ),
        );
      },
    ),
  );

  Widget _header(BuildContext context, ModernCalendarController controller) =>
      Padding(
        padding: PlayraLayout.pagePadding(context),
        child: LayoutBuilder(
          builder: (context, bounds) {
            const title = Text(
              '放送日历',
              maxLines: 1,
              style: TextStyle(
                fontSize: PlayraType.pageTitle,
                fontWeight: FontWeight.w700,
              ),
            );
            final period = PlayraButton.ghost(
              key: const ValueKey('calendar-season'),
              onPressed: () => _showSeason(context),
              trailing: const Icon(
                LucideIcons.chevronDown,
                size: PlayraLayout.compactIcon,
              ),
              child: Text(
                controller.seasonLabel,
                style: const TextStyle(fontSize: PlayraType.caption),
              ),
            );
            final stacked =
                bounds.maxWidth < 480 &&
                PlayraLayout.textScaleOf(context) > 1.4;
            return stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      Align(alignment: Alignment.centerRight, child: period),
                    ],
                  )
                : Row(
                    children: [
                      const Expanded(child: title),
                      period,
                    ],
                  );
          },
        ),
      );

  Widget _weekSelector(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final controller = widget.controller;
      final colors = Theme.of(context).colorScheme;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final width = (bounds.maxWidth / 7).clamp(
        PlayraLayout.touchTarget * scale,
        double.infinity,
      );
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
                duration: PlayraMotion.duration(context, PlayraMotion.state),
                curve: PlayraMotion.curve,
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
          height: math.max(
            PlayraLayout.touchTarget,
            MediaQuery.textScalerOf(context).scale(PlayraType.body) *
                    PlayraType.bodyHeight +
                MediaQuery.textScalerOf(context).scale(PlayraType.caption) *
                    PlayraType.bodyHeight +
                PlayraSpace.md,
          ),
          child: Row(
            children: [
              for (var day = 1; day <= 7; day++)
                SizedBox(
                  width: width,
                  child: Semantics(
                    selected: controller.weekday == day,
                    child: PlayraDayButton(
                      key: ValueKey('calendar-weekday-$day'),
                      selected: controller.weekday == day,
                      onPressed: () => controller.selectWeekday(day),

                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '周${'一二三四五六日'[day - 1]}',
                            style: TextStyle(
                              fontSize: PlayraType.body,
                              fontWeight: controller.weekday == day
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: PlayraSpace.xs),
                          Text(
                            controller.currentSeason && controller.today == day
                                ? '今天'
                                : controller.snapshot == null
                                ? '—'
                                : '${controller.dayEntries(day).length}部',
                            style: TextStyle(
                              fontSize: PlayraType.caption,
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
        ),
      );
    },
  );

  Widget _toolbar(BuildContext context, ModernCalendarController controller) {
    final filters = [
      if (controller.region != ScheduleRegion.all)
        controller.region == ScheduleRegion.japanese ? '日漫' : '国漫',
      if (controller.hideWatched) '隐藏看过',
      if (controller.hideAbandoned) '隐藏抛弃',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PlayraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: PlayraSpace.sm,
            runSpacing: PlayraSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PlayraChoice(
                label: const Text('全部'),
                selected: !controller.watchingOnly,
                onSelected: (_) => controller.setFilters(watchingOnly: false),
              ),
              PlayraChoice(
                label: const Text('仅追番'),
                selected: controller.watchingOnly,
                onSelected: (_) => controller.setFilters(watchingOnly: true),
              ),
              PlayraButton.ghost(
                key: const ValueKey('calendar-filters'),
                icon: const Icon(
                  LucideIcons.slidersHorizontal,
                  size: PlayraLayout.compactIcon,
                ),
                onPressed: () => _showFilters(context),
                child: Text(filters.isEmpty ? '筛选' : '筛选 · ${filters.length}'),
              ),
              if (!controller.isToday)
                PlayraButton.ghost(
                  onPressed: controller.goToday,
                  child: const Text('今天'),
                ),
            ],
          ),
          if (filters.isNotEmpty) ...[
            const SizedBox(height: PlayraSpace.sm),
            Text(
              filters.join(' · '),
              style: TextStyle(
                fontSize: PlayraType.caption,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterButton(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback? onTap,
  ) => PlayraChoice(
    label: Text(label),
    selected: selected,
    onSelected: onTap == null ? null : (_) => onTap(),
  );

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
            padding: PlayraLayout.pagePadding(
              context,
              top: PlayraSpace.sm,
              bottom: 10,
            ),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '周${'一二三四五六日'[day - 1]}放送',
                      style: const TextStyle(
                        fontSize: PlayraType.item,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    controller.snapshot == null
                        ? controller.loading
                              ? '加载中'
                              : '加载失败'
                        : '${items.length}部',
                    style: TextStyle(
                      fontSize: PlayraType.small,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (controller.snapshot != null &&
              (controller.error != null || controller.snapshot?.notice != null))
            SliverPadding(
              padding: PlayraLayout.pagePadding(
                context,
                top: 0,
                bottom: PlayraSpace.md,
              ),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.error ?? controller.snapshot!.notice!,
                        style: TextStyle(
                          fontSize: PlayraType.caption,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (controller.error != null)
                      PlayraButton.ghost(
                        onPressed: controller.refresh,
                        child: const Text('重试'),
                      ),
                  ],
                ),
              ),
            ),
          if (controller.loading && controller.snapshot == null)
            SliverPadding(
              padding: PlayraLayout.pagePadding(context),
              sliver: const SliverToBoxAdapter(child: SkeletonInfoList()),
            ),
          if (items.isEmpty &&
              (controller.snapshot != null || !controller.loading))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PlayraSpace.xl,
                  vertical: PlayraSpace.xxl,
                ),
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.calendarDays,
                      size: 30,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: PlayraSpace.md),
                    Text(
                      controller.snapshot == null
                          ? '暂时无法获取放送日历'
                          : controller.hasFilters
                          ? '没有符合筛选的番剧'
                          : '这一天暂无放送',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: PlayraSpace.sm),
                    Text(
                      controller.snapshot == null
                          ? '请检查网络连接后重试'
                          : controller.watchingOnly
                          ? '当前筛选下没有正在追看的番剧，可以查看全部放送'
                          : '可以切换星期或调整筛选条件',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: PlayraType.caption,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: PlayraSpace.lg),
                    if (controller.snapshot == null)
                      PlayraButton.outline(
                        onPressed: controller.refresh,
                        child: const Text('重新加载'),
                      )
                    else if (controller.hasFilters)
                      PlayraButton.ghost(
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
          const SliverToBoxAdapter(child: SizedBox(height: PlayraSpace.xxl)),
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
          padding: PlayraLayout.pagePadding(
            context,
            top: PlayraSpace.xs,
            bottom: 10,
          ),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 13,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(PlayraRadius.indicator),
                  ),
                ),
                const SizedBox(width: PlayraSpace.sm),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: PlayraType.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${entries.length}部',
                  style: TextStyle(
                    fontSize: PlayraType.small,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      SliverPadding(
        padding: PlayraLayout.pagePadding(context),
        sliver: SliverLayoutBuilder(
          builder: (context, bounds) {
            final scale = PlayraLayout.textScaleOf(context);
            final columns = PlayraLayout.columns(
              bounds.crossAxisExtent,
              minimum: 310,
              textScale: scale,
              maximum: 2,
            );
            Widget buildItem(BuildContext context, int index) {
              final entry = entries[index];
              final history = controller.historyFor(entry.item.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: PlayraSpace.md),
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
            }

            return columns == 1
                ? SliverList.builder(
                    itemCount: entries.length,
                    itemBuilder: buildItem,
                  )
                : SliverGrid.builder(
                    itemCount: entries.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 158 + 100 * math.max(0, scale - 1),
                      crossAxisSpacing: PlayraSpace.lg,
                    ),
                    itemBuilder: buildItem,
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
                style: TextStyle(
                  fontSize: PlayraType.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: PlayraSpace.sm),
              Wrap(
                spacing: PlayraSpace.sm,
                runSpacing: PlayraSpace.compact,
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
              const SizedBox(height: PlayraSpace.xl),
              const Text(
                '排序',
                style: TextStyle(
                  fontSize: PlayraType.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: PlayraSpace.sm),
              Wrap(
                spacing: PlayraSpace.sm,
                runSpacing: PlayraSpace.compact,
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
              const SizedBox(height: PlayraSpace.md),
              PlayraListGroup(
                children: [
                  PlayraSwitchTile(
                    title: const Text(
                      '隐藏看过',
                      style: TextStyle(fontSize: PlayraType.body),
                    ),
                    value: controller.hideWatched,
                    onChanged: (value) =>
                        controller.setFilters(hideWatched: value),
                  ),
                  PlayraSwitchTile(
                    title: const Text(
                      '隐藏抛弃',
                      style: TextStyle(fontSize: PlayraType.body),
                    ),
                    value: controller.hideAbandoned,
                    onChanged: (value) =>
                        controller.setFilters(hideAbandoned: value),
                  ),
                ],
              ),
              const SizedBox(height: PlayraSpace.lg),
              PlayraButton.outline(
                onPressed: controller.clearFilters,
                child: const Text('重置筛选'),
              ),
              PlayraButton.ghost(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onStyle();
                },
                child: const Text(
                  '切换新旧页面样式',
                  style: TextStyle(fontSize: PlayraType.caption),
                ),
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
      expandContent: true,
    );
  }

  Future<void> _sheet(
    BuildContext context,
    String? title,
    Widget Function(BuildContext) content, {
    bool expandContent = false,
  }) => showPlayraSheet<void>(
    context: context,
    title: title,
    size: expandContent ? PlayraSheetSize.standard : PlayraSheetSize.action,
    maxHeightFactor: expandContent ? .84 : .8,
    builder: (context) => Padding(
      padding: PlayraLayout.pagePadding(
        context,
        top: 0,
        bottom: PlayraSpace.xl,
      ),
      child: expandContent
          ? SizedBox(height: 600, child: content(context))
          : SingleChildScrollView(child: content(context)),
    ),
  );
}
