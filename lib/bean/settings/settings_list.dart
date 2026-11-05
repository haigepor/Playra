import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:flutter/material.dart';

import 'package:kazumi/bean/widget/content_section.dart';
import 'package:kazumi/bean/widget/split_list_row.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

enum _TileKind { plain, toggle, radio }

class SettingsList extends StatelessWidget {
  const SettingsList({super.key, required this.sections, this.maxWidth = 1000});

  final List<Widget> sections;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: PlayraSpace.md),
      itemCount: sections.length,
      itemBuilder: (context, index) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ModernSettingsScope.isActiveOf(context) ? 760 : maxWidth,
          ),
          child: sections[index],
        ),
      ),
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.tiles,
    this.title,
    this.bottomInfo,
    this.margin,
  });

  final List<Widget> tiles;
  final Widget? title;
  final Widget? bottomInfo;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding:
          margin ??
          (ModernSettingsScope.isActiveOf(context)
              ? EdgeInsets.fromLTRB(
                  PlayraLayout.pageInset(MediaQuery.sizeOf(context)),
                  0,
                  PlayraLayout.pageInset(MediaQuery.sizeOf(context)),
                  PlayraSpace.xxl,
                )
              : const EdgeInsets.fromLTRB(
                  PlayraSpace.lg,
                  0,
                  PlayraSpace.lg,
                  PlayraSpace.lg,
                )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                ModernSettingsScope.isActiveOf(context) ? 2 : 16,
                0,
                16,
                8,
              ),
              child: SectionHeader(title: title!),
            ),
          SplitListGroup(children: tiles),
          if (bottomInfo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PlayraSpace.lg,
                PlayraSpace.sm,
                PlayraSpace.lg,
                0,
              ),
              child: DefaultTextStyle.merge(
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                child: bottomInfo!,
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsRadioSection<T> extends StatelessWidget {
  const SettingsRadioSection({
    super.key,
    required this.groupValue,
    required this.onChanged,
    required this.tiles,
    this.title,
  });

  final T? groupValue;
  final ValueChanged<T?> onChanged;
  final List<Widget> tiles;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<T>(
      groupValue: groupValue,
      onChanged: onChanged,
      child: SettingsSection(title: title, tiles: tiles),
    );
  }
}

Color _disabledOn(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38);

class _TileLabel extends StatelessWidget {
  const _TileLabel({
    required this.title,
    this.leading,
    this.description,
    this.enabled = true,
  });

  final Widget title;
  final IconData? leading;
  final Widget? description;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final disabled = enabled ? null : _disabledOn(context);
    final foreground = disabled ?? colorScheme.onSurface;
    final secondary = disabled ?? colorScheme.onSurfaceVariant;

    return Row(
      children: [
        if (leading != null) ...[
          Icon(
            ModernSettingsScope.isActiveOf(context)
                ? modernSettingsIcon(leading!)
                : leading,
            size: ModernSettingsScope.isActiveOf(context) ? 20 : 24,
            color: secondary,
          ),
          SizedBox(width: ModernSettingsScope.isActiveOf(context) ? 12 : 16),
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(
                style: textTheme.bodyLarge?.copyWith(color: foreground),
                child: title,
              ),
              if (description != null) ...[
                const SizedBox(height: PlayraSpace.tiny),
                DefaultTextStyle.merge(
                  style: textTheme.bodySmall?.copyWith(color: secondary),
                  child: description!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsCategoryTile extends StatelessWidget {
  const SettingsCategoryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final modern = ModernSettingsScope.isActiveOf(context);
    if (PlayraComponentScope.enabledOf(context)) {
      return PlayraListTile(
        title: Text(title),
        subtitle: Text(description),
        onTap: onTap,
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(PlayraRadius.control),
          ),
          child: Padding(
            padding: const EdgeInsets.all(PlayraSpace.sm),
            child: Icon(
              modern ? modernSettingsIcon(icon) : icon,
              size: PlayraLayout.icon,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          size: PlayraLayout.compactIcon,
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      onHighlightChanged: SplitListRow.pressReporterOf(context),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: modern ? 14 : PlayraSpace.lg,
          vertical: PlayraSpace.md,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: modern
                    ? BorderRadius.circular(10)
                    : BorderRadius.circular(18),
              ),
              child: Icon(
                modern ? modernSettingsIcon(icon) : icon,
                size: 18,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            SizedBox(width: modern ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.bodyLarge),
                  const SizedBox(height: PlayraSpace.tiny),
                  Text(
                    description,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: modern ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              modern ? LucideIcons.chevronRight : Icons.chevron_right_rounded,
              size: modern ? 16 : null,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsSliderTile extends StatelessWidget {
  const SettingsSliderTile({
    super.key,
    required this.title,
    required this.value,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.leading,
    this.description,
  });

  final Widget title;
  final IconData? leading;
  final Widget? description;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PlayraSpace.lg,
        PlayraSpace.md,
        PlayraSpace.lg,
        PlayraSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _TileLabel(
                  title: title,
                  leading: leading,
                  description: description,
                ),
              ),
              const SizedBox(width: PlayraSpace.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: PlayraSpace.xs,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(PlayraRadius.thumbnail),
                ),
                child: Text(
                  valueLabel,
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: ModernSettingsScope.isActiveOf(context) ? 4 : 8),
          // 手柄缩小后仍保留 48dp 的拖动区域，安卓上更容易操作。
          ConstrainedBox(
            constraints: ModernSettingsScope.isActiveOf(context)
                ? const BoxConstraints.tightFor(height: 48)
                : const BoxConstraints(),
            child: PlayraSlider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,

              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsTile<T> extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.leading,
    this.description,
    this.trailing,
    this.value,
    this.onPressed,
    this.enabled = true,
  }) : _kind = _TileKind.plain,
       onToggle = null,
       initialValue = null,
       radioValue = null;

  /// Row taps pass null to [onToggle]; switch gestures pass the new value.
  const SettingsTile.switchTile({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onToggle,
    this.leading,
    this.description,
    this.enabled = true,
  }) : _kind = _TileKind.toggle,
       trailing = null,
       value = null,
       onPressed = null,
       radioValue = null;

  const SettingsTile.radioTile({
    super.key,
    required this.title,
    required T this.radioValue,
    this.leading,
    this.description,
    this.enabled = true,
  }) : _kind = _TileKind.radio,
       trailing = null,
       value = null,
       onPressed = null,
       onToggle = null,
       initialValue = null;

  final Widget title;

  final IconData? leading;
  final Widget? description;
  final Widget? trailing;
  final Widget? value;
  final void Function(BuildContext context)? onPressed;
  final void Function(bool? value)? onToggle;
  final bool? initialValue;
  final T? radioValue;
  final bool enabled;
  final _TileKind _kind;

  VoidCallback? _tapHandler(BuildContext context) {
    if (!enabled) {
      return null;
    }
    switch (_kind) {
      case _TileKind.plain:
        return onPressed == null ? null : () => onPressed!(context);
      case _TileKind.toggle:
        return onToggle == null ? null : () => onToggle!(null);
      case _TileKind.radio:
        final registry = RadioGroup.maybeOf<T>(context);
        return registry == null ? null : () => registry.onChanged(radioValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final secondary = enabled
        ? colorScheme.onSurfaceVariant
        : _disabledOn(context);
    final modern = ModernSettingsScope.isActiveOf(context);

    final forui = PlayraComponentScope.enabledOf(context);
    final content = Padding(
      padding: forui
          ? EdgeInsets.zero
          : EdgeInsets.symmetric(
              horizontal: modern ? 14 : PlayraSpace.lg,
              vertical: PlayraSpace.md,
            ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final below =
                modern &&
                value != null &&
                constraints.maxWidth < 340 &&
                MediaQuery.textScalerOf(context).scale(14) > 18;
            final valueWidget = value == null
                ? null
                : DefaultTextStyle.merge(
                    style: textTheme.bodyMedium?.copyWith(color: secondary),
                    child: value!,
                  );
            final row = Row(
              children: [
                Expanded(
                  child: _TileLabel(
                    title: title,
                    leading: leading,
                    description: description,
                    enabled: enabled,
                  ),
                ),
                if (valueWidget != null && !below) ...[
                  const SizedBox(width: PlayraSpace.md),
                  if (modern)
                    // 只限制长值的最大宽度，让短值贴右而不是占半行。
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * .42,
                      ),
                      child: valueWidget,
                    )
                  else
                    valueWidget,
                ],
                if (trailing != null) ...[
                  const SizedBox(width: PlayraSpace.sm),
                  IconTheme.merge(
                    data: IconThemeData(color: secondary),
                    child: trailing!,
                  ),
                ],
                if (_kind == _TileKind.toggle) ...[
                  const SizedBox(width: PlayraSpace.md),
                  if (modern && !forui)
                    // 只缩小绘制尺寸；命中检测保留原开关的触摸范围。
                    Transform.scale(
                      scale: .8,
                      alignment: Alignment.centerRight,
                      transformHitTests: false,
                      child: PlayraSwitch(
                        value: initialValue ?? false,
                        onChanged: enabled ? onToggle : null,
                      ),
                    )
                  else
                    PlayraSwitch(
                      value: initialValue ?? false,
                      onChanged: enabled ? onToggle : null,
                    ),
                ],
                if (_kind == _TileKind.radio) ...[
                  const SizedBox(width: PlayraSpace.md),
                  PlayraRadio<T>(value: radioValue as T, enabled: enabled),
                ],
                if (modern &&
                    _kind == _TileKind.plain &&
                    onPressed != null &&
                    value == null &&
                    trailing == null)
                  Icon(LucideIcons.chevronRight, size: 16, color: secondary),
              ],
            );
            return below
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      row,
                      const SizedBox(height: PlayraSpace.sm),
                      valueWidget!,
                    ],
                  )
                : row;
          },
        ),
      ),
    );
    return InkWell(
      onTap: _tapHandler(context),
      onHighlightChanged: SplitListRow.pressReporterOf(context),
      child: content,
    );
  }
}
