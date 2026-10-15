import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

Duration sdkMotion(BuildContext context, [int milliseconds = 220]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// 两类播放页共用紧凑来源栏；分组和当前线路各占一层。
class PlaybackSourcePanel extends StatelessWidget {
  const PlaybackSourcePanel({
    super.key,
    required this.groups,
    required this.summary,
    required this.automatic,
    required this.onShowLines,
    this.lineCount = 0,
    this.detail,
    this.selectorKey,
    this.trailing,
  });
  final List<Widget> groups;
  final String summary;
  final bool automatic;
  final int lineCount;
  final String? detail;
  final VoidCallback? onShowLines;
  final Key? selectorKey;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final controlShape =
        (theme.outlinedButtonTheme.style?.shape?.resolve({}) ??
                const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ))
            .copyWith(side: BorderSide(color: colors.outline));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '播放源',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Wrap(spacing: 6, runSpacing: 2, children: groups)),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          container: true,
          button: true,
          label: '播放线路',
          child: Material(
            color: colors.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: controlShape,
            child: InkWell(
              key: selectorKey,
              onTap: onShowLines,
              customBorder: controlShape,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      automatic
                          ? Icons.auto_awesome_rounded
                          : Icons.alt_route_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(summary, style: theme.textTheme.labelLarge),
                          if (detail != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                detail!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$lineCount 条',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PlaybackSdkChip extends StatelessWidget {
  const PlaybackSdkChip({
    super.key,
    required this.name,
    required this.selected,
    required this.onSelected,
  });
  final String name;
  final bool selected;
  final VoidCallback? onSelected;
  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(name),
    showCheckmark: false,
    selected: selected,
    onSelected: onSelected == null ? null : (_) => onSelected!(),
  );
}

/// 只保留自动模式与当前状态；线路信息按站点分组，避免重复站名和说明。
class PlaybackLineSheet extends StatelessWidget {
  const PlaybackLineSheet({
    super.key,
    required this.sdkName,
    required this.automaticOption,
    required this.children,
    required this.onClose,
  });
  final String sdkName;
  final Widget automaticOption;
  final List<Widget> children;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).bottomSheetTheme.dragHandleColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Text(
                  '选择线路',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sdkName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭线路选择',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: automaticOption,
          ),
          const SizedBox(height: 4),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: children,
            ),
          ),
        ],
      ),
    ),
  );
}

class PlaybackRouteChip extends StatelessWidget {
  const PlaybackRouteChip({
    super.key,
    required this.name,
    required this.episodeCount,
    required this.onTap,
    this.selected = false,
    this.current = false,
  });
  final String name;
  final int episodeCount;
  final VoidCallback onTap;
  final bool selected, current;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$episodeCount 集',
    excludeFromSemantics: true,
    child: Semantics(
      label: '$name，$episodeCount 集${current ? "，当前使用" : ""}',
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        avatar: current
            ? Icon(
                Icons.play_arrow_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              )
            : selected
            ? const Icon(Icons.check_rounded, size: 16)
            : null,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (selected || current
                            ? Theme.of(context).chipTheme.secondaryLabelStyle
                            : Theme.of(context).chipTheme.labelStyle)
                        ?.copyWith(
                          color: selected || current
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
              ),
            ),
            if (current) ...[
              const SizedBox(width: 6),
              Text(
                '当前',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
        color: current
            ? WidgetStatePropertyAll(
                Theme.of(
                  context,
                ).chipTheme.color?.resolve({WidgetState.selected}),
              )
            : null,
        side: BorderSide(
          color: selected || current
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        onSelected: (_) => onTap(),
      ),
    ),
  );
}

/// SVG 只提供结构，颜色完全跟随现有主题 token。
class SdkSourceGlyph extends StatelessWidget {
  const SdkSourceGlyph({super.key, this.automatic = false, this.size = 22});
  final bool automatic;
  final double size;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    automatic ? 'assets/images/sdk-auto.svg' : 'assets/images/sdk-route.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
    colorFilter: ColorFilter.mode(
      Theme.of(context).colorScheme.primary,
      BlendMode.srcIn,
    ),
  );
}

class SdkSourceDecoration extends StatelessWidget {
  const SdkSourceDecoration({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Opacity(
      opacity: .12,
      child: SvgPicture.asset(
        'assets/images/sdk-orbit.svg',
        width: 150,
        height: 94,
        excludeFromSemantics: true,
        colorFilter: ColorFilter.mode(
          Theme.of(context).colorScheme.primary,
          BlendMode.srcIn,
        ),
      ),
    ),
  );
}

class SdkLineOption extends StatelessWidget {
  const SdkLineOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.automatic = false,
    this.selected = false,
    this.current = false,
  });
  final String title, subtitle;
  final VoidCallback onTap;
  final bool automatic, selected, current;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected
              ? colors.secondaryContainer
              : colors.surfaceContainerLow,
          shape: theme.chipTheme.shape,
          child: InkWell(
            onTap: onTap,
            customBorder: theme.chipTheme.shape,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (automatic) ...[
                    const SdkSourceGlyph(automatic: true, size: 20),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (current && !selected)
                          Text(
                            '当前使用',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
