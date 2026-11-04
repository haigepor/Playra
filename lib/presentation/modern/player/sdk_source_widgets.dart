import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

Duration sdkMotion(BuildContext context, [int milliseconds = 220]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// 两类播放页共用紧凑来源栏：左右布局，左侧「播放源」标签，右侧当前源。
///
/// 2026-11-03 重设计：只显示播放源与切换入口——线路名称、分辨率、清晰度
/// 这类描述全部移入点击后的弹窗；行内不再出现任何长文案。
class PlaybackSourcePanel extends StatelessWidget {
  const PlaybackSourcePanel({
    super.key,
    required this.sourceLabel,
    this.onSelectSource,
    this.trailing,
    this.selectorKey,
    this.title = '播放源',
    this.height = 48,
  });
  final String sourceLabel;
  final VoidCallback? onSelectSource;
  final Widget? trailing;
  final Key? selectorKey;
  final String title;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(
              // 无障碍节点与点击目标挂在同一层：读屏与自动化都只命中一个按钮。
              child: Semantics(
                key: selectorKey,
                container: true,
                button: true,
                label: '$title ${sourceLabel.isEmpty ? "未设置" : sourceLabel}',
                child: InkWell(
                  onTap: onSelectSource,
                  customBorder: const StadiumBorder(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cast_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 源名独占剩余宽度并右对齐：Spacer 与 Flexible 平分会把
                        // 「动漫 · Lumina」这类长源名提前截断。
                        Expanded(
                          child: Text(
                            sourceLabel.isEmpty ? '选择播放源' : sourceLabel,
                            maxLines: 1,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ?trailing,
            const SizedBox(width: 6),
          ],
        ),
      ),
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
    this.sources,
    this.quality,
  });
  final String sdkName;
  final Widget automaticOption;
  final List<Widget> children;
  final VoidCallback onClose;

  /// 多供给方时的来源切换区（顶部）。
  final Widget? sources;

  /// 画质选择区（底部）；单链无多档时为 null。
  final Widget? quality;
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
          if (sources != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: sources!,
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
          if (quality != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: quality!,
            ),
          ],
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
