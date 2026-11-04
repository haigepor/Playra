import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;
import 'package:kazumi/presentation/widgets/playra_controls.dart';

typedef KazumiMenuBuilder =
    Widget Function(BuildContext context, VoidCallback? toggle);

const _menuItemStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(144, 48)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
  alignment: AlignmentDirectional.centerStart,
  visualDensity: VisualDensity.standard,
);

class KazumiMenuButton extends StatelessWidget {
  const KazumiMenuButton({
    super.key,
    required this.builder,
    required this.menuChildren,
    this.controller,
    this.enabled = true,
    this.animated = false,
    this.crossAxisUnconstrained = true,
    this.onOpen,
    this.onClose,
    this.style,
  });

  final KazumiMenuBuilder builder;
  final List<Widget> menuChildren;
  final MenuController? controller;
  final bool enabled;

  /// Opt in only for menus that previously animated.
  final bool animated;
  final bool crossAxisUnconstrained;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final MenuStyle? style;

  @override
  Widget build(BuildContext context) {
    if (PlayraComponentScope.enabledOf(context)) {
      return f.FPopoverMenu.tiles(
        maxHeight: MediaQuery.sizeOf(context).height * .65,
        menuBuilder: (context, popover, _) => [
          f.FTileGroup(
            children: [
              for (final item in menuChildren)
                _foruiItem(item, () => popover.hide()),
            ],
          ),
        ],
        builder: (context, popover, _) => builder(
          context,
          enabled && menuChildren.isNotEmpty ? () => popover.toggle() : null,
        ),
      );
    }
    return MenuButtonTheme(
      data: MenuButtonThemeData(
        // Submenu entries must use the same inset as ordinary menu items.
        style: _menuItemStyle.merge(MenuButtonTheme.of(context).style),
      ),
      child: MenuAnchor(
        controller: controller,
        consumeOutsideTap: true,
        crossAxisUnconstrained: crossAxisUnconstrained,
        animated: animated && !MediaQuery.disableAnimationsOf(context),
        onOpen: onOpen,
        onClose: onClose,
        style: style,
        menuChildren: menuChildren,
        builder: (context, controller, _) => builder(
          context,
          enabled && menuChildren.isNotEmpty
              ? () => controller.isOpen ? controller.close() : controller.open()
              : null,
        ),
      ),
    );
  }
}

f.FTileMixin _foruiItem(Widget item, VoidCallback close) {
  if (item is KazumiMenuItem) {
    return f.FTile(
      title: Text(item.label),
      prefix: item.leadingIcon,
      selected: item.selected ?? false,
      enabled: item.onPressed != null,
      variant: item.destructive
          ? f.FItemVariant.destructive
          : f.FItemVariant.primary,
      suffix: item.selected == true
          ? const Icon(Icons.check_rounded, size: 18)
          : null,
      onPress: item.onPressed == null
          ? null
          : () {
              close();
              item.onPressed!();
            },
    );
  }
  if (item is SubmenuButton) {
    return f.FSubmenuTile(
      title: item.child ?? const SizedBox.shrink(),
      prefix: item.leadingIcon,
      menu: [
        f.FTileGroup(
          children: [
            for (final entry in item.menuChildren) _foruiItem(entry, close),
          ],
        ),
      ],
    );
  }
  return f.FTile(title: item);
}

class KazumiMenuItem extends StatelessWidget {
  const KazumiMenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.leadingIcon,
    this.selected,
    this.destructive = false,
    this.requestFocusOnHover = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? leadingIcon;

  /// Null for actions; a bool exposes single-choice selection semantics.
  final bool? selected;
  final bool destructive;
  final bool requestFocusOnHover;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = destructive
        ? colors.error
        : selected == true
        ? colors.primary
        : null;
    final foregroundColor = color == null
        ? null
        : WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.disabled) ? null : color,
          );
    return MenuItemButton(
      onPressed: onPressed,
      requestFocusOnHover: requestFocusOnHover,
      style: ButtonStyle(
        foregroundColor: foregroundColor,
        iconColor: foregroundColor,
      ),
      leadingIcon: leadingIcon,
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: selected == null ? null : true,
        child: Text(label, textAlign: TextAlign.start),
      ),
    );
  }
}
