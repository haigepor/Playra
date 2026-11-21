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
                message: '日历加载失败',
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
          else if (layout.showSideRail)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                layout.gutter,
                PlayraSpace.lg,
                layout.gutter,
                PlayraSpace.xxl,
              ),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  mainAxisExtent: 260,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final release = _dayReleases(_selectedDate)[index];
                  return _CalendarReleaseCard(
                    release: release,
                    vertical: true,
                    onTap: () => _openDetail(release.item),
                  );
                }, childCount: _dayReleases(_selectedDate).length),
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
    var typing = false;
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
    final t = PlayraHomeTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.gutter,
        layout.headerTopPadding,
        layout.gutter,
        0,
      ),
      child: SizedBox(
        height: layout.isPhone ? 44 : 48,
        child: Row(
          children: [
            Text(
              '更新日历',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: PlayraType.pageTitle,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const Spacer(),
            _MonthButton(
              date: selectedDate,
              onTap: onMonthTap,
              compact: layout.isPhone,
            ),
          ],
        ),
      ),
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
        minimumSize: const Size(0, 36),
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

class _WeekStrip extends StatelessWidget {
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

  static const _weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.gutter,
        PlayraSpace.sm,
        layout.gutter,
        0,
      ),
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 160) {
            onWeekChanged(-7);
          } else if (velocity < -160) {
            onWeekChanged(7);
          }
        },
        child: SizedBox(
          height:
              (MediaQuery.textScalerOf(context).scale(11) * 1.2 +
                      MediaQuery.textScalerOf(context).scale(16) +
                      24)
                  .clamp(54.0, double.infinity),
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _DayCell(
                    weekday: _weekdays[i],
                    date: weekStart.add(Duration(days: i)),
                    selected: _sameDay(
                      weekStart.add(Duration(days: i)),
                      selectedDate,
                    ),
                    today: _sameDay(weekStart.add(Duration(days: i)), today),
                    releaseCount: releases
                        .where(
                          (release) =>
                              release.weekday ==
                              weekStart.add(Duration(days: i)).weekday,
                        )
                        .length,
                    onTap: () =>
                        onDaySelected(weekStart.add(Duration(days: i))),
                  ),
                ),
            ],
          ),
        ),
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
    required this.releaseCount,
    required this.onTap,
  });

  final String weekday;
  final DateTime date;
  final bool selected;
  final bool today;
  final int releaseCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            weekday,
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
              border: Border(
                bottom: BorderSide(
                  width: 2,
                  color: selected ? t.accent : Colors.transparent,
                ),
              ),
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
          _ReleaseDots(count: releaseCount, selected: selected),
        ],
      ),
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
    final palette = PlayraHomeTokens.of(context);
    final timeWidth = MediaQuery.textScalerOf(context).scale(13) * 3.3;
    final layout = HomeLayoutMetrics.of(context);
    final titleWidth =
        MediaQuery.sizeOf(context).width -
        2 * layout.gutter -
        timeWidth -
        16 -
        80 -
        10 -
        44;
    final stackTime =
        titleWidth < MediaQuery.textScalerOf(context).scale(14) * 5;
    return Column(
      children: [
        for (var i = 0; i < releases.length; i++)
          Stack(
            children: [
              if (!stackTime)
                Positioned(
                  left: timeWidth,
                  width: 9,
                  top: 0,
                  bottom: 0,
                  child: Column(
                    children: [
                      Expanded(
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: i == 0 ? Colors.transparent : palette.divider,
                        ),
                      ),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.accent,
                        ),
                      ),
                      Expanded(
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: i == releases.length - 1
                              ? Colors.transparent
                              : palette.divider,
                        ),
                      ),
                    ],
                  ),
                ),
              _CalendarReleaseCard(
                release: releases[i],
                stackTime: stackTime,
                onTap: () => onTap(releases[i].item),
              ),
            ],
          ),
      ],
    );
  }
}

class _CalendarReleaseCard extends StatefulWidget {
  const _CalendarReleaseCard({
    required this.release,
    required this.onTap,
    this.vertical = false,
    this.stackTime = false,
  });

  final _CalendarRelease release;
  final VoidCallback onTap;
  final bool vertical;
  final bool stackTime;

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
    if (!widget.vertical) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: _buildHorizontal(context, t),
          ),
        ),
      );
    }

    final card = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.cardSurface.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _buildVertical(context, t),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      ),
    );
  }

  Widget _buildHorizontal(BuildContext context, PlayraHomeTokens t) {
    final release = widget.release;
    final time = Text(
      release.time,
      maxLines: 1,
      style: TextStyle(
        color: t.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        width: widget.stackTime ? 60 : 80,
        height: widget.stackTime ? 36 : 52,
        child: MediaCoverImage(
          url: release.item.cover,
          cacheWidth:
              ((widget.stackTime ? 60 : 80) *
                      MediaQuery.devicePixelRatioOf(context))
                  .round(),
          errorWidget: ColoredBox(
            color: t.cardPlaceholder,
            child: Icon(
              Icons.image_not_supported_outlined,
              color: t.textSecondary,
              size: 18,
            ),
          ),
        ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Row(
        children: [
          if (widget.stackTime)
            Column(children: [time, const SizedBox(height: 3), cover])
          else ...[
            SizedBox(
              width: MediaQuery.textScalerOf(context).scale(13) * 3.3,
              child: time,
            ),
            const SizedBox(width: 16),
            cover,
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  release.item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  release.episodeLabel,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 2),
          ValueListenableBuilder(
            valueListenable: FavoriteStorage.listenable(),
            builder: (context, box, child) =>
                _FollowButton(following: _following, onTap: _toggleFollow),
          ),
        ],
      ),
    );
  }

  Widget _buildVertical(BuildContext context, PlayraHomeTokens t) {
    final release = widget.release;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              release.time,
              style: TextStyle(
                color: t.accent,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            ValueListenableBuilder(
              valueListenable: FavoriteStorage.listenable(),
              builder: (context, box, child) =>
                  _FollowButton(following: _following, onTap: _toggleFollow),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SizedBox.expand(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MediaCoverImage(
                url: release.item.cover,
                cacheWidth: 720,
                errorWidget: ColoredBox(
                  color: t.cardPlaceholder,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: t.textSecondary,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          release.item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          release.episodeLabel,
          style: TextStyle(color: t.textSecondary, fontSize: 12),
        ),
      ],
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
        minimumSize: const Size(44, 44),
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

  var time = '待定';
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
