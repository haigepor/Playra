import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart' as f;

import '../theme/playra_forui_theme.dart';
import '../theme/playra_tokens.dart';
import 'playra_card.dart';
import 'playra_component_scope.dart';
export 'playra_component_scope.dart';

enum PlayraButtonKind { primary, secondary, outline, ghost, destructive }

class PlayraDayButton extends StatelessWidget with PlayraForuiComponent {
  const PlayraDayButton({
    super.key,
    required this.onPressed,
    required this.child,
  });
  final VoidCallback? onPressed;
  final Widget child;
  @override
  Widget buildForui(BuildContext context) => f.FButton(
    onPress: onPressed,
    variant: f.FButtonVariant.ghost,
    size: f.FButtonSizeVariant.lg,
    style: f.FButtonStyleDelta.delta(
      contentStyle: f.FButtonContentStyleDelta.delta(
        padding: const f.EdgeInsetsGeometryDelta.value(
          EdgeInsets.all(PlayraSpace.xs),
        ),
      ),
    ),
    child: child,
  );
}

class PlayraButton extends StatelessWidget with PlayraForuiComponent {
  const PlayraButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.trailing,
    this.kind = PlayraButtonKind.primary,
    this.iconAlignment = IconAlignment.start,
    this.busy = false,
  });
  const PlayraButton.tonal({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.trailing,
    this.iconAlignment = IconAlignment.start,
    this.busy = false,
  }) : kind = PlayraButtonKind.secondary;
  const PlayraButton.outline({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.trailing,
    this.iconAlignment = IconAlignment.start,
    this.busy = false,
  }) : kind = PlayraButtonKind.outline;
  const PlayraButton.ghost({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.trailing,
    this.iconAlignment = IconAlignment.start,
    this.busy = false,
  }) : kind = PlayraButtonKind.ghost;
  const PlayraButton.destructive({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.trailing,
    this.iconAlignment = IconAlignment.start,
    this.busy = false,
  }) : kind = PlayraButtonKind.destructive;
  const PlayraButton.icon({
    super.key,
    required this.onPressed,
    required Widget label,
    this.icon,
    this.kind = PlayraButtonKind.primary,
    this.iconAlignment = IconAlignment.start,
    this.busy = false,
  }) : child = label,
       trailing = null;
  const PlayraButton.tonalIcon({
    super.key,
    required this.onPressed,
    required Widget label,
    this.icon,
    this.iconAlignment = IconAlignment.start,
    this.busy = false,
  }) : child = label,
       trailing = null,
       kind = PlayraButtonKind.secondary;
  const PlayraButton.outlineIcon({
    super.key,
    required this.onPressed,
    required Widget label,
    this.icon,
    this.iconAlignment = IconAlignment.start,
    this.busy = false,
  }) : child = label,
       trailing = null,
       kind = PlayraButtonKind.outline;
  const PlayraButton.ghostIcon({
    super.key,
    required this.onPressed,
    required Widget label,
    this.icon,
    this.iconAlignment = IconAlignment.start,
    this.busy = false,
  }) : child = label,
       trailing = null,
       kind = PlayraButtonKind.ghost;
  const PlayraButton.destructiveIcon({
    super.key,
    required this.onPressed,
    required Widget label,
    this.icon,
    this.iconAlignment = IconAlignment.start,
    this.busy = false,
  }) : child = label,
       trailing = null,
       kind = PlayraButtonKind.destructive;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final Widget? trailing;
  final PlayraButtonKind kind;
  final IconAlignment iconAlignment;
  final bool busy;

  @override
  Widget buildForui(BuildContext context) {
    if (!PlayraComponentScope.enabledOf(context)) {
      final content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ] else if (icon != null) ...[
            icon!,
            const SizedBox(width: 8),
          ],
          child,
        ],
      );
      return kind == PlayraButtonKind.ghost
          ? TextButton(onPressed: busy ? null : onPressed, child: content)
          : FilledButton.tonal(onPressed: busy ? null : onPressed, child: content);
    }
    final variant = switch (kind) {
      PlayraButtonKind.primary => f.FButtonVariant.primary,
      PlayraButtonKind.secondary => f.FButtonVariant.secondary,
      PlayraButtonKind.outline => f.FButtonVariant.outline,
      PlayraButtonKind.ghost => f.FButtonVariant.ghost,
      PlayraButtonKind.destructive => f.FButtonVariant.destructive,
    };
    final effectivePrefix = busy
        ? const SizedBox.square(dimension: 16, child: f.FCircularProgress())
        : (iconAlignment == IconAlignment.start ? icon : null);
    return f.FButton(
      onPress: busy ? null : onPressed,
      variant: variant,
      size: f.FButtonSizeVariant.lg,
      mainAxisSize: MainAxisSize.min,
      prefix: effectivePrefix,
      suffix: trailing ?? (iconAlignment == IconAlignment.end && !busy ? icon : null),
      child: child,
    );
  }
}

class PlayraIconButton extends StatelessWidget with PlayraForuiComponent {
  const PlayraIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.isSelected,
    this.selectedIcon,
  });
  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final bool? isSelected;
  final Widget? selectedIcon;
  @override
  Widget buildForui(BuildContext context) {
    if (!PlayraComponentScope.enabledOf(context)) {
      return IconButton(
        onPressed: onPressed,
        icon: icon,
        tooltip: tooltip,
        isSelected: isSelected,
        selectedIcon: selectedIcon,
      );
    }
    final button = f.FButton.icon(
      onPress: onPressed,
      variant: f.FButtonVariant.ghost,
      size: f.FButtonSizeVariant.lg,
      selected: isSelected ?? false,
      semanticsLabel: tooltip,
      child: isSelected == true ? selectedIcon ?? icon : icon,
    );
    return tooltip == null
        ? button
        : f.FTooltip(tipBuilder: (_, _) => Text(tooltip!), child: button);
  }
}

/// Keeps controller, IME and validation contracts while Forui owns field visuals.
class PlayraTextField extends StatelessWidget with PlayraForuiComponent {
  const PlayraTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.onChanged,
    this.onSubmitted,
    this.onTapOutside,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enabled,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.smartDashesType,
    this.smartQuotesType,
  }) : validator = null,
       initialValue = null,
       _form = false;
  const PlayraTextField.form({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.onChanged,
    ValueChanged<String>? onFieldSubmitted,
    this.onTapOutside,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enabled,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.smartDashesType,
    this.smartQuotesType,
    this.validator,
    this.initialValue,
  }) : onSubmitted = onFieldSubmitted,
       _form = true;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TapRegionCallback? onTapOutside;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText, autocorrect, enableSuggestions, readOnly, autofocus;
  final bool? enabled;
  final int? maxLength, maxLines, minLines;
  final SmartDashesType? smartDashesType;
  final SmartQuotesType? smartQuotesType;
  final FormFieldValidator<String>? validator;
  final String? initialValue;
  final bool _form;
  @override
  Widget buildForui(BuildContext context) {
    final label =
        decoration.label ??
        (decoration.labelText == null ? null : Text(decoration.labelText!));
    final prefix = decoration.prefixIcon ?? decoration.prefix;
    final suffix = decoration.suffixIcon ?? decoration.suffix;
    final control = f.FTextFieldControl.managed(
      controller: controller,
      initial: initialValue == null
          ? null
          : TextEditingValue(text: initialValue!),
      onChange: onChanged == null ? null : (value) => onChanged!(value.text),
    );
    if (_form) {
      return f.FTextFormField(
        control: control,
        size: f.FTextFieldSizeVariant.lg,
        label: label,
        hint: decoration.hintText,
        description: decoration.helperText == null
            ? null
            : Text(decoration.helperText!),
        focusNode: focusNode,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        obscureText: obscureText,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        enabled: enabled ?? true,
        readOnly: readOnly,
        autofocus: autofocus,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: minLines,
        smartDashesType: smartDashesType,
        smartQuotesType: smartQuotesType,
        onSubmit: onSubmitted,
        onTapOutside: onTapOutside,
        validator: validator,
        prefixBuilder: prefix == null ? null : (_, _, _) => prefix,
        suffixBuilder: suffix == null ? null : (_, _, _) => suffix,
      );
    }
    return f.FTextField(
      control: control,
      size: f.FTextFieldSizeVariant.lg,
      label: label,
      hint: decoration.hintText,
      description: decoration.helperText == null
          ? null
          : Text(decoration.helperText!),
      error: decoration.errorText == null ? null : Text(decoration.errorText!),
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      enabled: enabled ?? true,
      readOnly: readOnly,
      autofocus: autofocus,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: minLines,
      smartDashesType: smartDashesType,
      smartQuotesType: smartQuotesType,
      onSubmit: onSubmitted,
      onTapOutside: onTapOutside,
      prefixBuilder: prefix == null ? null : (_, _, _) => prefix,
      suffixBuilder: suffix == null ? null : (_, _, _) => suffix,
    );
  }
}

class PlayraSwitch extends StatelessWidget with PlayraForuiComponent {
  const PlayraSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget buildForui(BuildContext context) =>
      !PlayraComponentScope.enabledOf(context)
      ? Switch(value: value, onChanged: onChanged)
      : ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: f.FSwitch(
            value: value,
            onChange: onChanged,
            enabled: onChanged != null,
          ),
        );
}

class PlayraCheckbox extends StatelessWidget with PlayraForuiComponent {
  const PlayraCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final String? semanticLabel;
  @override
  Widget buildForui(BuildContext context) =>
      !PlayraComponentScope.enabledOf(context)
      ? Checkbox(
          value: value,
          onChanged: onChanged,
          semanticLabel: semanticLabel,
        )
      : f.FCheckbox(
          value: value ?? false,
          onChange: onChanged,
          enabled: onChanged != null,
          semanticsLabel: semanticLabel,
        );
}

class PlayraSlider extends StatelessWidget with PlayraForuiComponent {
  const PlayraSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
  });
  final double value, min, max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  @override
  Widget buildForui(BuildContext context) =>
      !PlayraComponentScope.enabledOf(context)
      ? Slider(
          value: value,
          onChanged: onChanged,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
        )
      : f.FSlider(
          enabled: onChanged != null,
          trackHitRegionCrossExtent: PlayraLayout.touchTarget,
          control: f.FSliderControl.liftedContinuous(
            value: f.FSliderValue(max: (value - min) / (max - min)),
            interaction: f.FSliderInteraction.tapAndSlideThumb,
            onChange: (next) {
              var result = next.max * (max - min) + min;
              if (divisions != null) {
                result =
                    ((result - min) / (max - min) * divisions!).round() /
                        divisions! *
                        (max - min) +
                    min;
              }
              onChanged?.call(result.clamp(min, max));
            },
          ),
          semanticValueFormatterCallback: (fraction) =>
              label ?? (min + fraction * (max - min)).toStringAsFixed(1),
        );
}

/// RawRadio retains the existing group's arrow-key and focus behavior.
class PlayraRadio<T> extends StatefulWidget {
  const PlayraRadio({super.key, required this.value, this.enabled = true});
  final T value;
  final bool enabled;
  @override
  State<PlayraRadio<T>> createState() => _PlayraRadioState<T>();
}

class _PlayraRadioState<T> extends State<PlayraRadio<T>> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!PlayraComponentScope.enabledOf(context)) {
      return Radio<T>(value: widget.value, enabled: widget.enabled);
    }
    final registry = RadioGroup.maybeOf<T>(context);
    return RawRadio<T>(
      value: widget.value,
      enabled: widget.enabled && registry != null,
      groupRegistry: registry,
      focusNode: _focus,
      autofocus: false,
      toggleable: false,
      mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
      builder: (context, state) => ExcludeFocus(
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: f.FRadio(
                  value: state.value ?? false,
                  enabled: widget.enabled,
                  onChange: null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PlayraProgress extends StatelessWidget with PlayraForuiComponent {
  const PlayraProgress({super.key, this.value, this.semanticsLabel});
  final double? value;
  final String? semanticsLabel;
  @override
  Widget buildForui(BuildContext context) =>
      !PlayraComponentScope.enabledOf(context)
      ? LinearProgressIndicator(value: value, semanticsLabel: semanticsLabel)
      : value == null
      ? f.FProgress(semanticsLabel: semanticsLabel)
      : f.FDeterminateProgress(
          value: value!.clamp(0, 1),
          semanticsLabel: semanticsLabel,
        );
}

class PlayraSpinner extends StatelessWidget with PlayraForuiComponent {
  const PlayraSpinner({super.key});
  @override
  Widget buildForui(BuildContext context) =>
      !PlayraComponentScope.enabledOf(context)
      ? const CircularProgressIndicator()
      : const f.FCircularProgress();
}

class PlayraChoice extends StatelessWidget with PlayraForuiComponent {
  const PlayraChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  @override
  Widget buildForui(BuildContext context) => f.FButton(
    onPress: onSelected == null ? null : () => onSelected!(!selected),
    selected: selected,
    variant: selected ? f.FButtonVariant.secondary : f.FButtonVariant.outline,
    size: f.FButtonSizeVariant.md,
    mainAxisSize: MainAxisSize.min,
    prefix: selected
        ? const Icon(Icons.check_rounded, size: PlayraLayout.compactIcon)
        : null,
    child: label,
  );
}

class PlayraDialog extends StatelessWidget with PlayraForuiComponent {
  const PlayraDialog({
    super.key,
    this.title,
    this.content,
    this.icon,
    this.actions = const [],
    this.constraints,
    this.scrollable = false,
  });
  final Widget? title, content, icon;
  final List<Widget>? actions;
  final BoxConstraints? constraints;
  final bool scrollable;
  @override
  Widget buildForui(BuildContext context) =>
      !PlayraComponentScope.enabledOf(context)
      ? AlertDialog(
          title: title,
          content: content,
          icon: icon,
          actions: actions,
          constraints: constraints,
          scrollable: scrollable,
        )
      : PlayraForuiScope(
          child: f.FDialog(
            constraints:
                constraints ??
                const BoxConstraints(
                  minWidth: 0,
                  maxWidth: PlayraLayout.actionSheetWidth,
                ),
            builder: (context, style) => Padding(
              padding: const EdgeInsets.all(PlayraSpace.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (icon != null) ...[
                    icon!,
                    const SizedBox(height: PlayraSpace.lg),
                  ],
                  if (title != null) ...[
                    DefaultTextStyle(
                      style: style.titleTextStyle,
                      child: title!,
                    ),
                    const SizedBox(height: PlayraSpace.lg),
                  ],
                  if (content != null)
                    Flexible(
                      child: SingleChildScrollView(
                        child: DefaultTextStyle(
                          style: style.bodyTextStyle,
                          child: content!,
                        ),
                      ),
                    ),
                  if (actions?.isNotEmpty ?? false) ...[
                    const SizedBox(height: PlayraSpace.xl),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: PlayraSpace.sm,
                      runSpacing: PlayraSpace.sm,
                      children: actions!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
}

class PlayraListTile extends StatelessWidget with PlayraForuiComponent {
  const PlayraListTile({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });
  final Widget? title, subtitle, leading, trailing;
  final VoidCallback? onTap;
  final bool enabled;
  @override
  Widget buildForui(BuildContext context) => f.FTile(
    title: title ?? const SizedBox.shrink(),
    subtitle: subtitle,
    prefix: leading,
    suffix: trailing,
    onPress: enabled ? onTap : null,
    enabled: enabled,
  );
}

class PlayraListGroup extends StatelessWidget with PlayraForuiComponent {
  const PlayraListGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget buildForui(BuildContext context) => f.FTileGroup(
    children: [for (final child in children) _PlayraTileSlot(child: child)],
  );
}

class _PlayraTileSlot extends StatelessWidget with f.FTileMixin {
  const _PlayraTileSlot({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class PlayraSurface extends StatelessWidget with PlayraForuiComponent {
  const PlayraSurface({super.key, required this.child, this.margin});
  final Widget child;
  final EdgeInsetsGeometry? margin;
  @override
  Widget buildForui(BuildContext context) => Padding(
    padding: margin ?? const EdgeInsets.all(PlayraSpace.xs),
    child: PlayraCard(padding: EdgeInsets.zero, child: child),
  );
}

class PlayraSwitchTile extends StatelessWidget with PlayraForuiComponent {
  const PlayraSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget title;
  final Widget? subtitle;
  @override
  Widget buildForui(BuildContext context) => f.FTile(
    title: title,
    subtitle: subtitle,
    enabled: onChanged != null,
    onPress: onChanged == null ? null : () => onChanged!(!value),
    suffix: PlayraSwitch(value: value, onChanged: onChanged),
  );
}

class PlayraCheckboxTile extends StatelessWidget with PlayraForuiComponent {
  const PlayraCheckboxTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
  });
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final Widget title;
  final Widget? subtitle;
  @override
  Widget buildForui(BuildContext context) => f.FTile(
    title: title,
    subtitle: subtitle,
    enabled: onChanged != null,
    onPress: onChanged == null ? null : () => onChanged!(!(value ?? false)),
    suffix: PlayraCheckbox(value: value, onChanged: onChanged),
  );
}

class PlayraRadioTile<T> extends StatelessWidget {
  const PlayraRadioTile({
    super.key,
    required this.value,
    required this.title,
    this.subtitle,
    this.secondary,
    this.enabled = true,
    this.selected = false,
  });
  final T value;
  final Widget title;
  final Widget? subtitle, secondary;
  final bool enabled, selected;
  @override
  Widget build(BuildContext context) => f.FTile(
    title: title,
    subtitle: subtitle,
    prefix: secondary,
    enabled: enabled,
    selected: selected,
    onPress: enabled
        ? () => RadioGroup.maybeOf<T>(context)?.onChanged(value)
        : null,
    suffix: PlayraRadio<T>(value: value, enabled: enabled),
  );
}

class PlayraExpansionTile extends StatelessWidget with PlayraForuiComponent {
  const PlayraExpansionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.children = const [],
    this.initiallyExpanded = false,
  });
  final Widget title;
  final Widget? subtitle, leading;
  final List<Widget> children;
  final bool initiallyExpanded;
  @override
  Widget buildForui(BuildContext context) => f.FAccordion(
    children: [
      f.FAccordionItem(
        initiallyExpanded: initiallyExpanded,
        title: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: PlayraSpace.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, ?subtitle],
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ],
  );
}

/// The existing TabController still owns routing and swipe synchronization.
class PlayraTabBar extends StatelessWidget
    with PlayraForuiComponent
    implements PreferredSizeWidget {
  const PlayraTabBar({
    super.key,
    required this.tabs,
    this.controller,
    this.onTap,
    this.isScrollable = false,
  });
  final List<Widget> tabs;
  final TabController? controller;
  final ValueChanged<int>? onTap;
  final bool isScrollable;
  @override
  Size get preferredSize => const Size.fromHeight(PlayraLayout.toolbar);
  @override
  Widget buildForui(BuildContext context) {
    final current = controller ?? DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: current,
      builder: (context, _) => f.FTabs(
        scrollable: isScrollable,
        // 选项卡只用文字颜色区分选中，不画整条底色或选中指示块。
        style: f.FTabsStyleDelta.delta(
          decoration: f.DecorationDelta.value(
            const BoxDecoration(color: Colors.transparent),
          ),
          indicatorDecoration: f.DecorationDelta.value(
            const BoxDecoration(color: Colors.transparent),
          ),
        ),
        control: f.FTabControl.lifted(
          index: current.index,
          motion: f.FTabMotion(
            duration: PlayraMotion.duration(context, PlayraMotion.state),
            curve: PlayraMotion.curve,
          ),
          onChange: (index) => current.animateTo(
            index,
            duration: PlayraMotion.duration(context, PlayraMotion.state),
          ),
        ),
        onPress: onTap,
        children: [
          for (final tab in tabs)
            f.FTabEntry(
              label: tab is Tab
                  ? KeyedSubtree(
                      key: tab.key,
                      child: tab.child ?? Text(tab.text ?? ''),
                    )
                  : tab,
              child: const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

class PlayraSearchBar extends StatelessWidget with PlayraForuiComponent {
  const PlayraSearchBar({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.leading,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  });
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final Widget? leading;
  final Iterable<Widget>? trailing;
  final ValueChanged<String>? onChanged, onSubmitted;
  final TextInputAction? textInputAction;
  @override
  Widget buildForui(BuildContext context) => PlayraTextField(
    controller: controller,
    focusNode: focusNode,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    textInputAction: textInputAction,
    decoration: InputDecoration(
      hintText: hintText,
      prefixIcon: leading,
      suffixIcon: trailing == null
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: trailing!.toList()),
    ),
  );
}

class PlayraPopupMenu<T> extends StatelessWidget {
  const PlayraPopupMenu({
    super.key,
    required this.itemBuilder,
    this.onSelected,
    this.initialValue,
    this.tooltip,
    this.child,
    this.icon,
  });
  final List<PopupMenuEntry<T>> Function(BuildContext) itemBuilder;
  final ValueChanged<T>? onSelected;
  final T? initialValue;
  final String? tooltip;
  final Widget? child, icon;
  @override
  Widget build(BuildContext context) => f.FPopoverMenu.tiles(
    maxHeight: MediaQuery.sizeOf(context).height * .65,
    menuBuilder: (context, control, _) => [
      f.FTileGroup(
        children: [
          for (final entry in itemBuilder(context))
            if (entry is PopupMenuItem<T>)
              f.FTile(
                title: entry.child ?? const SizedBox.shrink(),
                selected: entry.value == initialValue,
                enabled: entry.enabled,
                onPress: !entry.enabled
                    ? null
                    : () {
                        control.hide();
                        entry.onTap?.call();
                        if (entry.value != null) {
                          onSelected?.call(entry.value as T);
                        }
                      },
              ),
        ],
      ),
    ],
    builder: (context, control, _) => child == null
        ? PlayraIconButton(
            tooltip: tooltip,
            onPressed: () => control.toggle(),
            icon: icon ?? const Icon(Icons.more_vert_rounded),
          )
        : f.FTappable(onPress: () => control.toggle(), child: child!),
  );
}

class PlayraDialogSurface extends StatelessWidget with PlayraForuiComponent {
  const PlayraDialogSurface({super.key, required this.child, this.constraints})
    : fullscreen = false;
  const PlayraDialogSurface.fullscreen({super.key, required this.child})
    : fullscreen = true,
      constraints = null;
  final Widget child;
  final BoxConstraints? constraints;
  final bool fullscreen;
  @override
  Widget buildForui(BuildContext context) => PlayraForuiScope(
    child: f.FDialog(
      clipBehavior: Clip.antiAlias,
      constraints: fullscreen
          ? BoxConstraints.tight(MediaQuery.sizeOf(context))
          : constraints ??
                const BoxConstraints(maxWidth: PlayraLayout.sheetWidth),
      builder: (_, _) => child,
    ),
  );
}

enum PlayraBadgeKind { primary, secondary, outline, destructive }

class PlayraBadge extends StatelessWidget with PlayraForuiComponent {
  const PlayraBadge({
    super.key,
    required this.child,
    this.kind = PlayraBadgeKind.primary,
  });

  const PlayraBadge.secondary({
    super.key,
    required this.child,
  }) : kind = PlayraBadgeKind.secondary;

  const PlayraBadge.outline({
    super.key,
    required this.child,
  }) : kind = PlayraBadgeKind.outline;

  const PlayraBadge.destructive({
    super.key,
    required this.child,
  }) : kind = PlayraBadgeKind.destructive;

  final Widget child;
  final PlayraBadgeKind kind;

  @override
  Widget buildForui(BuildContext context) {
    final tokens = context.playraTokens;
    final (bg, fg, border) = switch (kind) {
      PlayraBadgeKind.primary => (tokens.primary, tokens.primaryForeground, null),
      PlayraBadgeKind.secondary => (tokens.surfaceRaised, tokens.foreground, tokens.borderSubtle),
      PlayraBadgeKind.outline => (Colors.transparent, tokens.foreground, tokens.borderSubtle),
      PlayraBadgeKind.destructive => (tokens.destructive, tokens.destructiveContainer, null),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PlayraTokens.radiusSm),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        child: child,
      ),
    );
  }
}

enum PlayraAlertKind { primary, destructive }

class PlayraAlert extends StatelessWidget with PlayraForuiComponent {
  const PlayraAlert({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.kind = PlayraAlertKind.primary,
  });

  const PlayraAlert.destructive({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
  }) : kind = PlayraAlertKind.destructive;

  final Widget title;
  final Widget? subtitle;
  final Widget? icon;
  final PlayraAlertKind kind;

  @override
  Widget buildForui(BuildContext context) {
    final tokens = context.playraTokens;
    final isDestructive = kind == PlayraAlertKind.destructive;
    final bg = isDestructive ? tokens.destructiveContainer : tokens.surfaceRaised;
    final borderColor = isDestructive ? tokens.destructive : tokens.borderSubtle;
    final iconColor = isDestructive ? tokens.destructive : tokens.primary;

    return Container(
      padding: const EdgeInsets.all(PlayraSpace.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PlayraTokens.radiusLg),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            IconTheme(
              data: IconThemeData(color: iconColor, size: 20),
              child: icon!,
            ),
            const SizedBox(width: PlayraSpace.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultTextStyle.merge(
                  style: TextStyle(
                    color: tokens.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  child: title,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: PlayraSpace.xs),
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      color: tokens.foregroundMuted,
                      fontSize: 13,
                    ),
                    child: subtitle!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PlayraDivider extends StatelessWidget with PlayraForuiComponent {
  const PlayraDivider({
    super.key,
    this.vertical = false,
  });

  final bool vertical;

  @override
  Widget buildForui(BuildContext context) {
    final tokens = context.playraTokens;
    return vertical
        ? VerticalDivider(color: tokens.borderSubtle, width: 1, thickness: 1)
        : Divider(color: tokens.borderSubtle, height: 1, thickness: 1);
  }
}

class PlayraFloatingActionButton extends StatelessWidget with PlayraForuiComponent {
  const PlayraFloatingActionButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.tooltip,
  }) : label = null,
       icon = null;

  const PlayraFloatingActionButton.extended({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.tooltip,
  }) : child = null;

  final VoidCallback? onPressed;
  final Widget? child;
  final Widget? label;
  final Widget? icon;
  final String? tooltip;

  @override
  Widget buildForui(BuildContext context) {
    final tokens = context.playraTokens;
    final isExtended = label != null;
    final shape = isExtended
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PlayraTokens.radiusLg),
          )
        : const CircleBorder();

    final content = isExtended
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  icon!,
                  const SizedBox(width: 8),
                ],
                label!,
              ],
            ),
          )
        : SizedBox(
            width: 56,
            height: 56,
            child: Center(child: child),
          );

    final button = Material(
      color: tokens.primary,
      elevation: 4,
      shadowColor: Colors.black38,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: shape,
        child: IconTheme(
          data: IconThemeData(color: tokens.primaryForeground, size: 24),
          child: DefaultTextStyle(
            style: TextStyle(
              color: tokens.primaryForeground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            child: content,
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}
