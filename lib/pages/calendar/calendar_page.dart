import 'package:kazumi/pages/discover/media_widgets.dart';
import 'package:kazumi/presentation/widgets/playra_page_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/features/sources/sources.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';
import 'package:kazumi/presentation/widgets/playra_backdrop.dart';
import 'package:kazumi/presentation/widgets/playra_page_header.dart';
import 'package:kazumi/services/storage/storage.dart';

/// Weekly anime release calendar.
///
/// The content source currently exposes only a per-work `updateSchedule`
/// string. This page derives the weekly schedule from that field; if a source
/// has no usable schedule it shows an explicit empty state rather than
/// inventing air times.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _selectedDate;
  late DateTime _weekStart;
  List<_CalendarRelease> _releases = const [];
  Object? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _selectedDate = today;
    _weekStart = _startOfWeek(today);
    _load();
  }

  Future<void> _load() async {
    final source = mediaSources.primary;
    if (source == null) {
      setState(() {
        _isLoading = false;
        _error = '尚未注册任何内容源';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final feed = await source.loadHome();
      final seen = <String>{};
      final parsed = <_CalendarRelease>[];
      for (final section in feed.sections) {
        for (final item in section.items) {
          final identity = item.key.toString();
          if (!seen.add(identity)) continue;
          final schedule = _parseSchedule(item.updateSchedule);
          if (schedule == null) continue;
          parsed.add(
            _CalendarRelease(
              item: item,
              weekday: schedule.weekday,
              time: schedule.time,
              episodeLabel: _episodeLabel(item),
            ),
          );
        }
      }
      parsed.sort((a, b) {
        final byDay = a.weekday.compareTo(b.weekday);
        if (byDay != 0) return byDay;
        return a.time.compareTo(b.time);
      });
      if (!mounted) return;
      setState(() {
        _releases = parsed;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error;
      });
    }
  }

  Future<void> _refresh() async {
    mediaSources.primary?.invalidateCache();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayoutMetrics.of(context);
    final t = PlayraHomeTokens.of(context);
    return PlayraBackdrop(child: _buildContent(context, layout, t));
  }

  Widget _buildContent(
    BuildContext context,
    HomeLayoutMetrics layout,
    PlayraHomeTokens t,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPane =
            !layout.isPhone &&
            constraints.maxWidth >= 900 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20;
        return RefreshIndicator(
          onRefresh: _refresh,
          color: t.accent,
          backgroundColor: t.cardSurface,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _CalendarHeader(
                  selectedDate: _selectedDate,
                  onMonthTap: _pickMonth,
                  showMonth: !twoPane,
                ),
              ),
              if (twoPane)
                SliverToBoxAdapter(child: _buildWideContent(context, layout))
              else ...[
                SliverToBoxAdapter(
                  child: _WeekStrip(
                    layout: layout,
                    weekStart: _weekStart,
                    selectedDate: _selectedDate,
                    releases: _releases,
                    onDaySelected: (date) =>
                        setState(() => _selectedDate = date),
                    onWeekChanged: _changeWeek,
                  ),
                ),
                if (!_isLoading && _error == null)
                  SliverToBoxAdapter(
                    child: _SummaryRow(
                      layout: layout,
                      selectedDate: _selectedDate,
                      dayReleases: _dayReleases(_selectedDate),
                    ),
                  ),
                if (_isLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: MediaErrorState(
                      message: '更新内容暂未加载',
                      error: _error,
                      onRetry: _load,
                    ),
                  )
                else if (_dayReleases(_selectedDate).isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: PlayraPageState(
                      icon: Icons.calendar_today_outlined,
                      title: '这一天暂无更新',
                      action: FilledButton(
                        onPressed: _load,
                        child: const Text('刷新'),
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        layout.gutter,
                        PlayraSpace.xs,
                        layout.gutter,
                        0,
                      ),
                      child: _CalendarReleaseList(
                        releases: _dayReleases(_selectedDate),
                        onTap: _openDetail,
                      ),
                    ),
                  ),
              ],
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.paddingOf(context).bottom + PlayraSpace.lg,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWideContent(BuildContext context, HomeLayoutMetrics layout) {
    final t = PlayraHomeTokens.of(context);
    final releases = _dayReleases(_selectedDate);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.gutter),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 328,
            child: Material(
              color: t.cardSurface,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: _PlayraDatePicker(
                key: const ValueKey('playra-calendar-picker'),
                initialDate: _selectedDate,
                firstDate: _firstSelectableDate(_selectedDate),
                lastDate: _lastSelectableDate(_selectedDate),
                onDateChanged: (date) => setState(() {
                  _selectedDate = _dateOnly(date);
                  _weekStart = _startOfWeek(_selectedDate);
                }),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WeekStrip(
                  layout: layout,
                  weekStart: _weekStart,
                  selectedDate: _selectedDate,
                  releases: _releases,
                  onDaySelected: (date) => setState(() => _selectedDate = date),
                  onWeekChanged: _changeWeek,
                  embedded: true,
                ),
                if (!_isLoading && _error == null)
                  _SummaryRow(
                    layout: layout,
                    selectedDate: _selectedDate,
                    dayReleases: releases,
                    embedded: true,
                  ),
                if (_isLoading)
                  const SizedBox(
                    height: 280,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  SizedBox(
                    height: 280,
                    child: MediaErrorState(
                      message: '更新内容暂未加载',
                      error: _error,
                      onRetry: _load,
                    ),
                  )
                else if (releases.isEmpty)
                  SizedBox(
                    height: 280,
                    child: PlayraPageState(
                      icon: Icons.calendar_today_outlined,
                      title: '这一天暂无更新',
                      action: FilledButton(
                        onPressed: _load,
                        child: const Text('刷新'),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: PlayraSpace.xs),
                    child: _CalendarReleaseList(
                      releases: releases,
                      onTap: _openDetail,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_CalendarRelease> _dayReleases(DateTime date) {
    final day = date.weekday;
    return _releases.where((release) => release.weekday == day).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  void _changeWeek(int deltaDays) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: deltaDays));
      _selectedDate = _selectedDate.add(Duration(days: deltaDays));
    });
  }

  Future<void> _pickMonth() async {
    final first = _firstSelectableDate(_selectedDate);
    final last = _lastSelectableDate(_selectedDate);
    var draft = _selectedDate;
    var typing =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    final form = GlobalKey<FormState>();
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, update) {
          void confirm() {
            if (typing) {
              final input = form.currentState!;
              if (!input.validate()) return;
              input.save();
            }
            Navigator.pop(sheet, draft);
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '选择日期',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: typing ? '切换到日历模式' : '切换到输入模式',
                          icon: Icon(
                            typing
                                ? Icons.calendar_month_outlined
                                : Icons.edit_outlined,
                            size: 20,
                          ),
                          onPressed: () {
                            if (typing) form.currentState!.save();
                            update(() => typing = !typing);
                          },
                        ),
                        IconButton(
                          tooltip: '关闭日期选择',
                          onPressed: () => Navigator.pop(sheet),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: typing
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Form(
                                key: form,
                                child: InputDatePickerFormField(
                                  initialDate: draft,
                                  firstDate: first,
                                  lastDate: last,
                                  autofocus: true,
                                  onDateSaved: (date) => draft = date,
                                  onDateSubmitted: (date) =>
                                      Navigator.pop(sheet, date),
                                ),
                              ),
                            )
                          : _PlayraDatePicker(
                              key: const ValueKey('playra-calendar-picker'),
                              initialDate: draft,
                              firstDate: first,
                              lastDate: last,
                              onDateChanged: (date) => draft = date,
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 4),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(sheet),
                          child: const Text('取消'),
                        ),
                        FilledButton.tonal(
                          onPressed: confirm,
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = _dateOnly(picked);
      _weekStart = _startOfWeek(_selectedDate);
    });
  }

  void _openDetail(MediaItem item) {
    context.pushNamed('/detail', arguments: item.key);
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.selectedDate,
    required this.onMonthTap,
    this.showMonth = true,
  });

  final DateTime selectedDate;
  final VoidCallback onMonthTap;
  final bool showMonth;

  @override
  Widget build(BuildContext context) {
    return PlayraPageHeader(
      title: '日历',
      largeTitle: true,
      actions: [
        if (showMonth) _MonthButton(date: selectedDate, onTap: onMonthTap),
      ],
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: t.textPrimary,
        backgroundColor: t.searchFill.withValues(alpha: 0.78),
        shape: StadiumBorder(
          side: BorderSide(color: t.divider.withValues(alpha: 0.55)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(44, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${date.year}年',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Text(
            '${date.month}月',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: t.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _WeekStrip extends StatefulWidget {
  const _WeekStrip({
    required this.layout,
    required this.weekStart,
    required this.selectedDate,
    required this.releases,
    required this.onDaySelected,
    required this.onWeekChanged,
    this.embedded = false,
  });

  final bool embedded;
  final HomeLayoutMetrics layout;
  final DateTime weekStart;
  final DateTime selectedDate;
  final List<_CalendarRelease> releases;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<int> onWeekChanged;

  @override
  State<_WeekStrip> createState() => _WeekStripState();
}

class _WeekStripState extends State<_WeekStrip> {
  final _scroll = ScrollController();
  DateTime? _revealed;
  double? _revealedWidth;
  double? _revealedCellWidth;
  static const _weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final today = _dateOnly(DateTime.now());
    final reduceMotion = PlayraMotion.reduceOf(context);
    final weekEnd = widget.weekStart.add(const Duration(days: 6));
    final weekLabel =
        '${widget.weekStart.month}月${widget.weekStart.day}日 – ${weekEnd.month}月${weekEnd.day}日';
    final navStyle = TextButton.styleFrom(
      minimumSize: const Size(48, 34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.embedded ? 0 : widget.layout.gutter,
        widget.embedded ? 0 : PlayraSpace.sm,
        widget.embedded ? 0 : widget.layout.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            decoration: BoxDecoration(
              color: t.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: t.divider.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  style: navStyle,
                  onPressed: () => widget.onWeekChanged(-7),
                  icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  label: const Text('上周', style: TextStyle(fontSize: 13)),
                ),
                Text(
                  weekLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                TextButton.icon(
                  style: navStyle,
                  onPressed: () => widget.onWeekChanged(7),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  label: const Text('下周', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final scaler = MediaQuery.textScalerOf(context);
              final minimum = (scaler.scale(11) * 2.4 + 8)
                  .roundToDouble()
                  .clamp(48.0, double.infinity);
              const gap = 4.0;
              final idealCell = ((constraints.maxWidth - gap * 6) / 7)
                  .floorToDouble();
              final cellWidth = idealCell.clamp(minimum, double.infinity);
              final totalWidth = cellWidth * 7 + gap * 6;
              final selectedIdx = widget.selectedDate
                  .difference(widget.weekStart)
                  .inDays;
              final hasSelected = selectedIdx >= 0 && selectedIdx < 7;
              if (_revealed != widget.selectedDate ||
                  _revealedWidth != constraints.maxWidth ||
                  _revealedCellWidth != cellWidth) {
                _revealed = widget.selectedDate;
                _revealedWidth = constraints.maxWidth;
                _revealedCellWidth = cellWidth;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !_scroll.hasClients) return;
                  final index = widget.selectedDate
                      .difference(widget.weekStart)
                      .inDays;
                  _scroll.jumpTo(
                    (index * (cellWidth + gap) -
                            (constraints.maxWidth - cellWidth) / 2)
                        .clamp(0.0, _scroll.position.maxScrollExtent),
                  );
                });
              }
              return SizedBox(
                height: scaler.scale(11) * 1.2 + scaler.scale(16) + 46,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalWidth,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            for (var i = 0; i < 7; i++) ...[
                              if (i > 0) const SizedBox(width: gap),
                              Container(
                                width: cellWidth,
                                decoration: BoxDecoration(
                                  color: t.cardSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: t.divider.withValues(alpha: 0.35),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (hasSelected)
                          AnimatedPositioned(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            left: selectedIdx * (cellWidth + gap),
                            top: 0,
                            bottom: 0,
                            width: cellWidth,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: t.accent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            for (var i = 0; i < 7; i++) ...[
                              if (i > 0) const SizedBox(width: gap),
                              SizedBox(
                                width: cellWidth,
                                child: _DayCell(
                                  weekday: _weekdays[i],
                                  date: widget.weekStart.add(Duration(days: i)),
                                  selected: _sameDay(
                                    widget.weekStart.add(Duration(days: i)),
                                    widget.selectedDate,
                                  ),
                                  today: _sameDay(
                                    widget.weekStart.add(Duration(days: i)),
                                    today,
                                  ),
                                  onTap: () => widget.onDaySelected(
                                    widget.weekStart.add(Duration(days: i)),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.weekday,
    required this.date,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final String weekday;
  final DateTime date;
  final bool selected;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final reduceMotion = PlayraMotion.reduceOf(context);
    final dur = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortLabel =
            constraints.maxWidth <
            MediaQuery.textScalerOf(context).scale(11) * 2;
        return Semantics(
          button: true,
          selected: selected,
          label: '${date.month}月${date.day}日 $weekday${today ? ' 今天' : ''}',
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              hoverColor: selected
                  ? Colors.transparent
                  : t.accent.withValues(alpha: 0.08),
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onTap: onTap,
              child: ExcludeSemantics(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: dur,
                      style: TextStyle(
                        color: selected
                            ? t.accentForeground
                            : (today ? t.accent : t.textSecondary),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                      child: Text(
                        shortLabel ? weekday.substring(1) : weekday,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedDefaultTextStyle(
                      duration: dur,
                      style: TextStyle(
                        color: selected ? t.accentForeground : t.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                      child: Text('${date.day}'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.layout,
    required this.selectedDate,
    required this.dayReleases,
    this.embedded = false,
  });

  final HomeLayoutMetrics layout;
  final DateTime selectedDate;
  final List<_CalendarRelease> dayReleases;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final weekday = '一二三四五六日'[selectedDate.weekday - 1];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        embedded ? 0 : layout.gutter,
        PlayraSpace.md,
        embedded ? 0 : layout.gutter,
        0,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${selectedDate.month}月${selectedDate.day}日（周$weekday）',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            ' · 共 ${dayReleases.length} 部更新',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarReleaseList extends StatelessWidget {
  const _CalendarReleaseList({required this.releases, required this.onTap});
  final List<_CalendarRelease> releases;
  final ValueChanged<MediaItem> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final release in releases)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CalendarReleaseCard(
              release: release,
              onTap: () => onTap(release.item),
            ),
          ),
      ],
    );
  }
}

class _CalendarReleaseCard extends StatefulWidget {
  const _CalendarReleaseCard({required this.release, required this.onTap});

  final _CalendarRelease release;
  final VoidCallback onTap;

  @override
  State<_CalendarReleaseCard> createState() => _CalendarReleaseCardState();
}

class _CalendarReleaseCardState extends State<_CalendarReleaseCard> {
  bool get _following => FavoriteStorage.isFavorite(
    widget.release.item.key.sourceId,
    widget.release.item.key.mediaId,
  );

  Future<void> _toggleFollow() async {
    final item = widget.release.item;
    await FavoriteStorage.toggle(
      FavoriteRecord(
        sourceId: item.key.sourceId,
        mediaId: item.key.mediaId,
        title: item.title,
        cover: item.cover,
        category: item.category,
        subtitle: item.subtitle,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return Semantics(
      label: widget.release.time,
      child: Material(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: _buildHorizontal(context, t),
        ),
      ),
    );
  }

  Widget _buildHorizontal(BuildContext context, PlayraHomeTokens t) {
    final release = widget.release;
    final coverWidth = MediaQuery.sizeOf(context).shortestSide >= 600
        ? 112.0
        : 64.0;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: coverWidth,
              height: 72,
              child: MediaCoverImage(
                url: release.item.cover,
                fallbackUrl: release.item.fallbackCover,
                cacheWidth:
                    (coverWidth * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                errorWidget: ColoredBox(
                  color: t.cardPlaceholder,
                  child: Icon(
                    Icons.movie_outlined,
                    color: t.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  release.item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  release.time == '时间待定' ? release.time : '${release.time} 更新',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  release.episodeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder(
            valueListenable: FavoriteStorage.listenable(),
            builder: (context, box, child) =>
                _FollowButton(following: _following, onTap: _toggleFollow),
          ),
        ],
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.following, required this.onTap});

  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return IconButton(
      tooltip: following ? '取消追番' : '追番',
      onPressed: onTap,
      style: IconButton.styleFrom(
        foregroundColor: following ? t.accent : t.textSecondary,
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(
        following ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        size: 18,
      ),
    );
  }
}

class _PlayraDatePicker extends StatefulWidget {
  const _PlayraDatePicker({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateChanged;

  @override
  State<_PlayraDatePicker> createState() => _PlayraDatePickerState();
}

class _PlayraDatePickerState extends State<_PlayraDatePicker> {
  late DateTime _selected;
  late DateTime _displayedMonth;
  bool _yearMode = false;

  @override
  void initState() {
    super.initState();
    _selected = _dateOnly(widget.initialDate);
    _displayedMonth = DateTime(_selected.year, _selected.month);
  }

  @override
  void didUpdateWidget(covariant _PlayraDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameDay(oldWidget.initialDate, widget.initialDate)) {
      _selected = _dateOnly(widget.initialDate);
      _displayedMonth = DateTime(_selected.year, _selected.month);
    }
  }

  void _stepMonth(int delta) {
    final next = DateTime(_displayedMonth.year, _displayedMonth.month + delta);
    final firstMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    if (next.isBefore(firstMonth) || next.isAfter(lastMonth)) return;
    setState(() => _displayedMonth = next);
  }

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final today = _dateOnly(DateTime.now());
    final firstMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    final canPrev = _displayedMonth.isAfter(firstMonth);
    final canNext = _displayedMonth.isBefore(lastMonth);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  hoverColor: t.accent.withValues(alpha: 0.08),
                  splashColor: t.accent.withValues(alpha: 0.14),
                  onTap: () => setState(() => _yearMode = !_yearMode),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_displayedMonth.year}年${_displayedMonth.month}月',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _yearMode
                              ? Icons.arrow_drop_up_rounded
                              : Icons.arrow_drop_down_rounded,
                          size: 20,
                          color: t.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (!_yearMode) ...[
                IconButton(
                  tooltip: '上个月',
                  onPressed: canPrev ? () => _stepMonth(-1) : null,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                ),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: '下个月',
                  onPressed: canNext ? () => _stepMonth(1) : null,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: const Icon(Icons.chevron_right_rounded, size: 20),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (_yearMode)
            SizedBox(
              height: 236,
              child: GridView.builder(
                itemCount: widget.lastDate.year - widget.firstDate.year + 1,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisExtent: 42,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final year = widget.firstDate.year + index;
                  final selected = year == _displayedMonth.year;
                  final current = year == today.year;
                  return Material(
                    color: selected ? t.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      hoverColor: selected
                          ? Colors.transparent
                          : t.accent.withValues(alpha: 0.09),
                      splashColor: t.accent.withValues(alpha: 0.16),
                      onTap: () => setState(() {
                        _displayedMonth = DateTime(year, _displayedMonth.month);
                        _yearMode = false;
                      }),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: !selected && current
                              ? Border.all(color: t.accent, width: 1)
                              : null,
                        ),
                        child: Text(
                          '$year年',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected
                                ? t.accentForeground
                                : current
                                ? t.accent
                                : t.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          else ...[
            Row(
              children: [
                for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            color: t.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _buildDayGrid(context, t, today),
          ],
        ],
      ),
    );
  }

  Widget _buildDayGrid(
    BuildContext context,
    PlayraHomeTokens t,
    DateTime today,
  ) {
    final firstOfMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final daysInMonth =
        DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday - 1;
    final totalCells = ((leadingBlanks + daysInMonth + 6) ~/ 7) * 7;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalCells,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisExtent: 38,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final day = index - leadingBlanks + 1;
        if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
        final date = DateTime(_displayedMonth.year, _displayedMonth.month, day);
        final disabled =
            date.isBefore(widget.firstDate) || date.isAfter(widget.lastDate);
        final selected = _sameDay(date, _selected);
        final isToday = _sameDay(date, today);
        return Material(
          color: selected ? t.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            hoverColor: selected
                ? Colors.transparent
                : t.accent.withValues(alpha: 0.09),
            splashColor: t.accent.withValues(alpha: 0.16),
            onTap: disabled
                ? null
                : () {
                    setState(() => _selected = date);
                    widget.onDateChanged(date);
                  },
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: !selected && isToday
                    ? Border.all(color: t.accent, width: 1)
                    : null,
              ),
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: disabled
                      ? t.textSecondary.withValues(alpha: 0.35)
                      : selected
                      ? t.accentForeground
                      : isToday
                      ? t.accent
                      : t.textPrimary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CalendarRelease {
  const _CalendarRelease({
    required this.item,
    required this.weekday,
    required this.time,
    required this.episodeLabel,
  });

  final MediaItem item;
  final int weekday;
  final String time;
  final String episodeLabel;
}

class _ScheduleInfo {
  const _ScheduleInfo({required this.weekday, required this.time});

  final int weekday;
  final String time;
}

_ScheduleInfo? _parseSchedule(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final dayMatch = RegExp(r'(?:周|星期)([一二三四五六日天])').firstMatch(text);
  if (dayMatch == null) return null;
  final weekday = switch (dayMatch.group(1)) {
    '一' => 1,
    '二' => 2,
    '三' => 3,
    '四' => 4,
    '五' => 5,
    '六' => 6,
    '日' || '天' => 7,
    _ => 0,
  };
  if (weekday == 0) return null;

  var time = '时间待定';
  final timeMatch = RegExp(r'(\d{1,2})[:：点](\d{1,2})?').firstMatch(text);
  if (timeMatch != null) {
    final hour = int.tryParse(timeMatch.group(1) ?? '');
    final minute = int.tryParse(timeMatch.group(2) ?? '') ?? 0;
    if (hour != null &&
        hour >= 0 &&
        hour <= 23 &&
        minute >= 0 &&
        minute <= 59) {
      time =
          '${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')}';
    }
  }
  return _ScheduleInfo(weekday: weekday, time: time);
}

String _episodeLabel(MediaItem item) {
  if (item.subtitle.isNotEmpty) return item.subtitle;
  if (item.episodeCount > 0) return '${item.episodeCount} 集';
  return '待更新';
}

DateTime _firstSelectableDate(DateTime selected) =>
    selected.isBefore(DateTime(2020))
    ? DateTime(selected.year)
    : DateTime(2020);

DateTime _lastSelectableDate(DateTime selected) =>
    selected.isAfter(DateTime(2100))
    ? DateTime(selected.year + 1)
    : DateTime(2100);

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _startOfWeek(DateTime value) {
  final date = _dateOnly(value);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
