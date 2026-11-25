import 'package:flutter/material.dart';
import 'package:kazumi/shell/shell_theme.dart';

class PlayerOption<T> {
  const PlayerOption(
    this.value,
    this.label, {
    this.icon,
    this.detail,
    this.enabled = true,
    this.opensPage = false,
  });
  final T value;
  final String label;
  final IconData? icon;
  final String? detail;
  final bool enabled;
  final bool opensPage;
}

Future<T?> _playerSheet<T>(
  BuildContext context,
  String title,
  Widget content, {
  VoidCallback? onBack,
  bool narrow = false,
  bool scrollable = false,
}) => showDialog<T>(
  context: context,
  useSafeArea: false,
  barrierColor: Colors.black38,
  builder: (dialog) {
    final size = MediaQuery.sizeOf(dialog);
    final wide = size.width > size.height;
    final theme = buildShellTheme(Brightness.dark);
    final back = onBack == null
        ? null
        : () {
            onBack();
            Navigator.pop(dialog);
          };

    final panel = Material(
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: wide
          ? BorderRadius.zero
          : const BorderRadius.vertical(top: Radius.circular(20)),
      child: SizedBox(
        width: !wide
            ? size.width
            : narrow
            ? (size.width * .30).clamp(220.0, 300.0)
            : (size.width * .39).clamp(280.0, 405.0),
        height: wide ? size.height : null,
        child: SafeArea(
          top: wide,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: size.height * (wide ? 1 : .76),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!wide)
                  Container(
                    width: 30,
                    height: 3,
                    margin: const EdgeInsets.only(top: 8),
                    color: theme.colorScheme.outline,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 1, 4, 0),
                  child: Row(
                    children: [
                      if (onBack != null)
                        IconButton(
                          tooltip: '返回上一级',
                          onPressed: back,
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        ),
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭$title',
                        onPressed: () => Navigator.pop(dialog),
                        icon: const Icon(Icons.close_rounded, size: 19),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: scrollable
                      ? content
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                          child: content,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return PopScope<T>(
      canPop: onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back?.call();
      },
      child: Theme(
        data: theme,
        child: Align(
          alignment: wide ? Alignment.centerRight : Alignment.bottomCenter,
          child: wide
              ? panel
              : Dismissible(
                  key: ValueKey(title),
                  direction: DismissDirection.down,
                  resizeDuration: null,
                  dismissThresholds: const {DismissDirection.down: .22},
                  onDismissed: (_) => Navigator.pop(dialog),
                  child: panel,
                ),
        ),
      ),
    );
  },
);

Future<T?> showPlayerOptions<T>(
  BuildContext context, {
  required String title,
  required List<PlayerOption<T>> options,
  List<PlayerOption<T>> shortcuts = const [],
  T? selected,
  bool narrow = false,
  VoidCallback? onBack,
}) => _playerSheet<T>(
  context,
  title,
  Builder(
    builder: (sheet) {
      final theme = Theme.of(sheet);
      final colors = theme.colorScheme;
      return Column(
        children: [
          if (shortcuts.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final option in shortcuts)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: option.enabled
                          ? () => Navigator.pop(sheet, option.value)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 5,
                          horizontal: 2,
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                option.icon,
                                size: 22,
                                color: option.enabled
                                    ? colors.onSurface
                                    : theme.disabledColor,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              option.label,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: option.enabled
                                    ? colors.onSurface
                                    : theme.disabledColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          for (final option in options)
            Semantics(
              selected: selected == null ? null : selected == option.value,
              child: Ink(
                decoration: BoxDecoration(
                  color: selected == option.value
                      ? colors.primary.withValues(alpha: .14)
                      : colors.surfaceContainerHigh,
                  border: Border(
                    bottom: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: .35),
                    ),
                  ),
                ),
                child: InkWell(
                  onTap: option.enabled
                      ? () => Navigator.pop(sheet, option.value)
                      : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      child: Row(
                        children: [
                          if (option.icon != null) ...[
                            Icon(
                              option.icon,
                              size: 19,
                              color: selected == option.value
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option.label,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: !option.enabled
                                        ? theme.disabledColor
                                        : selected == option.value
                                        ? colors.primary
                                        : colors.onSurface,
                                  ),
                                ),
                                if (option.detail != null && shortcuts.isEmpty)
                                  Text(
                                    option.detail!,
                                    style: theme.textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          if (option.detail != null && shortcuts.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 110),
                              child: Text(
                                option.detail!,
                                textAlign: TextAlign.end,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          if (selected != null && !option.opensPage)
                            Icon(
                              selected == option.value
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 20,
                              color: selected == option.value
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            )
                          else if (option.opensPage)
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 17,
                              color: Colors.white38,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  ),
  narrow: narrow,
  onBack: onBack,
);

Future<int?> showRoadEpisodes(
  BuildContext context, {
  required String roadName,
  required List<PlayerOption<int>> episodes,
  required VoidCallback onBack,
}) => _playerSheet<int>(
  context,
  '$roadName · 选集',
  GridView.builder(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
    shrinkWrap: true,
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: MediaQuery.textScalerOf(
        context,
      ).scale(72).clamp(144.0, double.infinity),
      mainAxisExtent: (MediaQuery.textScalerOf(context).scale(14) * 4.0 + 20)
          .clamp(76.0, double.infinity),
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
    ),
    itemCount: episodes.length,
    itemBuilder: (context, i) {
      final ep = episodes[i];
      return Tooltip(
        message: [
          ep.label,
          if (ep.detail?.isNotEmpty == true) ep.detail!,
        ].join(' · '),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
          onPressed: ep.enabled ? () => Navigator.pop(context, ep.value) : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(ep.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (ep.detail?.isNotEmpty == true)
                Text(ep.detail!, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
    },
  ),
  onBack: onBack,
  scrollable: true,
);

Future<double?> showPlayerSpeed(
  BuildContext context,
  List<double> speeds,
  double selected, {
  VoidCallback? onBack,
}) => _playerSheet<double>(
  context,
  '倍速',
  _SpeedSelector(speeds: speeds, selected: selected),
  onBack: onBack,
);

class _SpeedSelector extends StatefulWidget {
  const _SpeedSelector({required this.speeds, required this.selected});
  final List<double> speeds;
  final double selected;
  @override
  State<_SpeedSelector> createState() => _SpeedSelectorState();
}

class _SpeedSelectorState extends State<_SpeedSelector> {
  late int index = widget.speeds
      .indexOf(widget.selected)
      .clamp(0, widget.speeds.length - 1);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rate = widget.speeds[index];
    final shortcuts = const [
      1.0,
      1.25,
      1.5,
      2.0,
    ].where(widget.speeds.contains).toList(growable: false);
    return Column(
      children: [
        const SizedBox(height: 12),
        Text(
          '$rate×',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            showValueIndicator: ShowValueIndicator.never,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: index.toDouble(),
            max: (widget.speeds.length - 1).toDouble(),
            divisions: widget.speeds.length - 1,
            semanticFormatterCallback: (v) => '${widget.speeds[v.round()]} 倍',
            onChanged: (v) => setState(() => index = v.round()),
            onChangeEnd: (v) =>
                Navigator.pop(context, widget.speeds[v.round()]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${widget.speeds.first}×',
                style: theme.textTheme.labelSmall,
              ),
              Text('${widget.speeds.last}×', style: theme.textTheme.labelSmall),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = MediaQuery.textScalerOf(context).scale(14) > 20
                ? 2
                : 4;
            const spacing = 8.0;
            final width =
                (constraints.maxWidth - (columns - 1) * spacing) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final value in shortcuts)
                  SizedBox(
                    width: width,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, value),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        minimumSize: const Size(48, 48),
                        backgroundColor: value == rate
                            ? colors.primary
                            : Colors.transparent,
                        foregroundColor: value == rate
                            ? colors.onPrimary
                            : colors.onSurface,
                        side: BorderSide(
                          color: value == rate
                              ? colors.primary
                              : colors.outline,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      child: Text('$value×', maxLines: 1),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
