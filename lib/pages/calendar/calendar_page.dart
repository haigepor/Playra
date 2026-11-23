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
    return RefreshIndicator(
      onRefresh: _refresh,
      color: t.accent,
      backgroundColor: t.cardSurface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _CalendarHeader(
              layout: layout,
              selectedDate: _selectedDate,
              onMonthTap: _pickMonth,
            ),
          ),
          SliverToBoxAdapter(
            child: _WeekStrip(
              layout: layout,
              weekStart: _weekStart,
              selectedDate: _selectedDate,
              releases: _releases,
              onDaySelected: (date) => setState(() => _selectedDate = date),
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
                action: FilledButton(onPressed: _load, child: const Text('刷新')),
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
          SliverToBoxAdapter(child: SizedBox(height: PlayraSpace.xxl)),
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
    final first = DateTime(2020);
    final last = DateTime(2100);
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
                          : CalendarDatePicker(
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
    required this.layout,
    required this.selectedDate,
    required this.onMonthTap,
  });

  final HomeLayoutMetrics layout;
  final DateTime selectedDate;
  final VoidCallback onMonthTap;

  @override
  Widget build(BuildContext context) {
    return PlayraPageHeader(
      title: '更新日历',
      largeTitle: true,
      actions: [
        _MonthButton(
          date: selectedDate,
          onTap: onMonthTap,
          compact: layout.isPhone,
        ),
      ],
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.date,
    required this.onTap,
    required this.compact,
  });

  final DateTime date;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: t.textPrimary,
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
        minimumSize: const Size(44, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            compact ? '${date.month}月' : '${date.year}年${date.month}月',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
  });

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
    final today = _dateOnly(DateTime.now());
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.layout.gutter,
        PlayraSpace.sm,
        widget.layout.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () => widget.onWeekChanged(-7),
                child: const Text('上周'),
              ),
              Text(
                '${widget.weekStart.month}/${widget.weekStart.day}–${widget.weekStart.add(const Duration(days: 6)).month}/${widget.weekStart.add(const Duration(days: 6)).day}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton(
                onPressed: () => widget.onWeekChanged(7),
                child: const Text('下周'),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final scaler = MediaQuery.textScalerOf(context);
              final minimum = (scaler.scale(11) * 2.4 + 8).clamp(
                48.0,
                double.infinity,
              );
              final cellWidth = (constraints.maxWidth / 7).clamp(
                minimum,
                double.infinity,
              );
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
                    (index * cellWidth - (constraints.maxWidth - cellWidth) / 2)
                        .clamp(0.0, _scroll.position.maxScrollExtent),
                  );
                });
              }
              return SizedBox(
                height: scaler.scale(11) * 1.2 + scaler.scale(16) + 30,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < 7; i++)
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortLabel =
            constraints.maxWidth <
            MediaQuery.textScalerOf(context).scale(11) * 2;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                shortLabel ? weekday.substring(1) : weekday,
                maxLines: 1,
                semanticsLabel: weekday,
                style: TextStyle(
                  color: today ? t.accent : t.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: PlayraMotion.duration(context, PlayraMotion.state),
                curve: PlayraMotion.curve,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 26),
                padding: const EdgeInsets.only(bottom: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? t.railSelected : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    color: selected ? t.accent : t.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _ReleaseDots(count: today ? 1 : 0, selected: selected),
            ],
          ),
        );
      },
    );
  }
}

class _ReleaseDots extends StatelessWidget {
  const _ReleaseDots({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return SizedBox(
      height: 5,
      child: count <= 0
          ? null
          : Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: selected
                    ? t.accentForeground.withValues(alpha: .78)
                    : t.accent.withValues(alpha: .55),
                shape: BoxShape.circle,
              ),
            ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.layout,
    required this.selectedDate,
    required this.dayReleases,
  });

  final HomeLayoutMetrics layout;
  final DateTime selectedDate;
  final List<_CalendarRelease> dayReleases;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final weekday = '一二三四五六日'[selectedDate.weekday - 1];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.gutter,
        PlayraSpace.sm,
        layout.gutter,
        0,
      ),
      child: Row(
        children: [
          Text(
            '每周$weekday',
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${dayReleases.length} 部',
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
        for (var i = 0; i < releases.length; i++) ...[
          if (i == 0 || releases[i].time != releases[i - 1].time)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 8 : 24, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ExcludeSemantics(
                  child: Text(
                    releases[i].time,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          _CalendarReleaseCard(
            release: releases[i],
            onTap: () => onTap(releases[i].item),
          ),
        ],
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
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: _buildHorizontal(context, t),
        ),
      ),
    );
  }

  Widget _buildHorizontal(BuildContext context, PlayraHomeTokens t) {
    final release = widget.release;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 48,
              height: 64,
              child: MediaCoverImage(
                url: release.item.cover,
                cacheWidth: (48 * MediaQuery.devicePixelRatioOf(context))
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
                const SizedBox(height: 6),
                Text(
                  release.episodeLabel,
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
  if (item.episodeCount > 0) return '第 ${item.episodeCount} 话';
  return item.subtitle.isEmpty ? '待更新' : item.subtitle;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _startOfWeek(DateTime value) {
  final date = _dateOnly(value);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
