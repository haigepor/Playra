import 'package:flutter/material.dart';
import '../../shadcn_gallery.dart';

class MyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MyAppBar({super.key, this.title, this.titleWidget});
  final String? title;
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    final controls = GalleryControls.of(context);
    return AppBar(
      title: titleWidget ?? Text(title ?? ''),
      actions: [
        IconButton(
          tooltip: '切换明暗主题',
          icon: Icon(controls.dark ? Icons.light_mode : Icons.dark_mode),
          onPressed: controls.toggleTheme,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
