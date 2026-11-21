import 'package:flutter/material.dart';

class PlayraBackdrop extends StatelessWidget {
  const PlayraBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: child,
  );
}
