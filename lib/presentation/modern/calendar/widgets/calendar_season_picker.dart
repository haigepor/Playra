import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/services/calendar/calendar_models.dart';

/// 年份与季度同屏编辑草稿，只有确认才切季和发起请求。
class CalendarSeasonPicker extends StatefulWidget {
  const CalendarSeasonPicker({
    super.key,
    required this.selectedSeason,
    required this.now,
    required this.onSelected,
    this.onClose,
  });

  final DateTime selectedSeason;
  final DateTime now;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback? onClose;

  @override
  State<CalendarSeasonPicker> createState() => _CalendarSeasonPickerState();
}

class _CalendarSeasonPickerState extends State<CalendarSeasonPicker> {
  static const _names = ['冬季', '春季', '夏季', '秋季'];
  static const _ranges = ['1–3月', '4–6月', '7–9月', '10–12月'];
  late int _year;
  late int _quarter;
  bool _submitted = false;
  int _yearPickerGeneration = 0;

  int get _earliestYear => widget.now.year - 20;
  DateTime get _current => calendarSeason(widget.now);
  DateTime get _draft => DateTime(_year, _quarter * 3 + 1);

  @override
  void initState() {
    super.initState();
    _year = widget.selectedSeason.year.clamp(_earliestYear, widget.now.year);
    _quarter = (calendarSeason(widget.selectedSeason).month - 1) ~/ 3;
    _clampQuarter();
  }

  void _clampQuarter() {
    // 历史秋季切回尚在春季的今年时，将草稿限制在已到来的季度。
    if (_draft.isAfter(_current)) _quarter = (_current.month - 1) ~/ 3;
  }

  void _selectYear(int year) => setState(() {
    _year = year;
    _clampQuarter();
  });

  void _resetCurrent() => setState(() {
    _year = _current.year;
    _quarter = (_current.month - 1) ~/ 3;
    // YearPicker 不公开滚动控制器；重建仅用于快捷键将今年滚回可见范围。
    _yearPickerGeneration++;
  });

  void _confirm() {
    if (_submitted || _draft.isAfter(_current)) return;
    _submitted = true;
    widget.onSelected(_draft);
  }

  WidgetStateProperty<Color?> _interactionOverlay(ColorScheme colors) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? colors.primary.withValues(alpha: .12)
            : Colors.transparent,
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final viewed = calendarSeason(widget.selectedSeason);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? math.min(600.0, constraints.maxHeight)
            : math.min(600.0, MediaQuery.sizeOf(context).height * .8);
        return SizedBox(
          key: const ValueKey('calendar-season-panel'),
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '选择放送季度',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '当前查看 · ${viewed.year} 年${_names[(viewed.month - 1) ~/ 3]}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      tooltip: '关闭',
                      onPressed: widget.onClose,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        overlayColor: Colors.transparent,
                      ),
                      icon: Icon(
                        LucideIcons.x,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, body) {
                    final quarterHeight = 136.0 + (scale - 1).clamp(0, 2) * 48;
                    // 矮屏/超大字体滚动主体，底部确认按钮不随内容滚走。
                    final scrollBody =
                        body.maxHeight < 44 + 44 + 28 + quarterHeight + 156;
                    final children = <Widget>[
                      _yearHeading(context),
                      if (scrollBody)
                        SizedBox(
                          height: 156 + (scale - 1).clamp(0, 2) * 52,
                          child: _yearPicker(context),
                        )
                      else
                        Expanded(child: _yearPicker(context)),
                      const SizedBox(height: 16),
                      _quarterHeading(context),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: quarterHeight,
                        child: _quarters(context),
                      ),
                    ];
                    return scrollBody
                        ? SingleChildScrollView(
                            key: const ValueKey('calendar-season-body-scroll'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: children,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: children,
                          );
                  },
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('calendar-season-confirm'),
                onPressed: _confirm,
                style: FilledButton.styleFrom(
                  minimumSize: Size(
                    double.infinity,
                    48 + (scale - 1).clamp(0, 2) * 16,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                  splashFactory: NoSplash.splashFactory,
                ),
                child: Text(
                  '查看 $_year 年 · ${_names[_quarter]}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _yearHeading(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const Text(
            '年份',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_earliestYear–${widget.now.year}',
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
            ),
          ),
          TextButton(
            key: const ValueKey('calendar-season-this-year'),
            onPressed: () => setState(() {
              _year = widget.now.year;
              _clampQuarter();
              _yearPickerGeneration++;
            }),
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurfaceVariant,
              minimumSize: const Size(44, 44),
              overlayColor: Colors.transparent,
              textStyle: const TextStyle(fontSize: 11),
            ),
            child: const Text('今年'),
          ),
        ],
      ),
    );
  }

  Widget _quarterHeading(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const Text(
            '季度',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_year 年',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ),
          TextButton.icon(
            key: const ValueKey('calendar-season-current'),
            onPressed: _resetCurrent,
            icon: Icon(LucideIcons.rotateCcw, size: 13, color: colors.primary),
            label: const Text('当前季度', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: colors.primary,
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              overlayColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _yearPicker(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.onSurface.withValues(alpha: .3);
      }
      return states.contains(WidgetState.selected)
          ? colors.primary
          : colors.onSurfaceVariant;
    });
    final background = WidgetStateProperty.resolveWith<Color?>(
      (states) => states.contains(WidgetState.selected)
          ? colors.primary.withValues(alpha: .14)
          : Colors.transparent,
    );
    return Theme(
      data: theme.copyWith(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        dividerTheme: const DividerThemeData(
          color: Colors.transparent,
          space: 0,
        ),
        datePickerTheme: theme.datePickerTheme.copyWith(
          yearStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          yearForegroundColor: foreground,
          yearBackgroundColor: background,
          todayForegroundColor: foreground,
          todayBackgroundColor: background,
          todayBorder: BorderSide.none,
          yearShape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          // 不显示点击/悬浮整块背景，键盘操作仍保留可见焦点。
          yearOverlayColor: _interactionOverlay(colors),
        ),
      ),
      child: YearPicker(
        key: ValueKey('calendar-season-years-$_yearPickerGeneration'),
        firstDate: DateTime(_earliestYear),
        lastDate: DateTime(widget.now.year, 12, 31),
        currentDate: widget.now,
        selectedDate: DateTime(_year, 1),
        onChanged: (date) => _selectYear(date.year),
      ),
    );
  }

  Widget _quarters(BuildContext context) => Column(
    children: [
      for (var row = 0; row < 2; row++) ...[
        if (row > 0) const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: [
              for (var column = 0; column < 2; column++) ...[
                if (column > 0) const SizedBox(width: 8),
                Expanded(child: _seasonCard(context, row * 2 + column)),
              ],
            ],
          ),
        ),
      ],
    ],
  );

  Widget _seasonCard(BuildContext context, int index) {
    final value = DateTime(_year, index * 3 + 1);
    final selected = index == _quarter;
    final enabled = !value.isAfter(_current);
    final colors = Theme.of(context).colorScheme;
    final foreground = enabled
        ? selected
              ? colors.primary
              : colors.onSurface
        : colors.onSurface.withValues(alpha: .3);
    return Semantics(
      selected: selected,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: .12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: .3)
                : colors.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('calendar-season-${index * 3 + 1}'),
            onTap: enabled ? () => setState(() => _quarter = index) : null,
            splashFactory: NoSplash.splashFactory,
            overlayColor: _interactionOverlay(colors),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _names[index],
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(
                          LucideIcons.check,
                          size: 15,
                          color: colors.primary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _ranges[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      color: enabled
                          ? colors.onSurfaceVariant
                          : colors.onSurface.withValues(alpha: .3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
