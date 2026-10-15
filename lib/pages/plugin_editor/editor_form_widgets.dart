import 'package:flutter/material.dart';
import 'package:kazumi/pages/plugin_editor/rule_management_widgets.dart';

class EditorTextField extends StatelessWidget {
  const EditorTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            autocorrect: false,
            enableSuggestions: true,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: maxLines > 1 ? 'monospace' : null,
              height: maxLines > 1 ? 1.6 : 1.4,
            ),
            decoration: ruleInputDecoration(context, hint: hint).copyWith(
              fillColor: theme.colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: .65,
                  ),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(
            helper!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class EditorChoiceGroup<T> extends StatelessWidget {
  const EditorChoiceGroup({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final T value;
  final List<ButtonSegment<T>> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      final wrap =
          constraints.maxWidth <
          segments.length * MediaQuery.textScalerOf(context).scale(64) +
              (segments.length - 1) * 4 +
              8;
      Widget button(int index) {
        final segment = segments[index];
        final selected = segment.value == value;
        return Semantics(
          selected: selected,
          inMutuallyExclusiveGroup: true,
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              backgroundColor: selected
                  ? colors.primary.withValues(alpha: .14)
                  : Colors.transparent,
              foregroundColor: selected
                  ? colors.primary
                  : colors.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            onPressed: segment.enabled ? () => onChanged(segment.value) : null,
            child: segment.label ?? segment.icon ?? const SizedBox.shrink(),
          ),
        );
      }

      final Widget choices;
      if (wrap) {
        choices = Wrap(
          spacing: 4,
          runSpacing: 4,
          children: List.generate(segments.length, button),
        );
      } else {
        choices = Row(
          children: [
            for (var index = 0; index < segments.length; index++) ...[
              if (index > 0) const SizedBox(width: 4),
              Expanded(child: button(index)),
            ],
          ],
        );
      }
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: choices,
      );
    },
  );
}

class EditorSegmentedField<T> extends StatelessWidget {
  const EditorSegmentedField({
    super.key,
    required this.label,
    required this.value,
    required this.segments,
    required this.onChanged,
    this.description,
  });

  final String label;
  final T value;
  final List<ButtonSegment<T>> segments;
  final ValueChanged<T> onChanged;
  final String Function(T value)? description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      EditorChoiceGroup<T>(
        value: value,
        segments: segments,
        onChanged: onChanged,
      ),
      if (description != null) ...[
        const SizedBox(height: 8),
        Text(
          description!(value),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ],
  );
}

class EditorAnimatedSection extends StatelessWidget {
  const EditorAnimatedSection({
    super.key,
    required this.activeKey,
    required this.child,
  });
  final Object activeKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250),
    curve: Curves.easeInOutCubicEmphasized,
    alignment: Alignment.topCenter,
    child: KeyedSubtree(key: ValueKey<Object>(activeKey), child: child),
  );
}

class EditorSubheader extends StatelessWidget {
  const EditorSubheader({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
