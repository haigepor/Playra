import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

class ModernPageScaffold extends StatelessWidget {
  const ModernPageScaffold({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        PlayraIconButton(
          tooltip: '页面样式',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => context.pushNamed('/settings/interface'),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          PlayraSpace.xl,
          PlayraSpace.sm,
          PlayraSpace.xl,
          PlayraSpace.xxl,
        ),
        children: children,
      ),
    ),
  );
}

class ModernSection extends StatelessWidget {
  const ModernSection({
    super.key,
    required this.title,
    required this.description,
    this.child,
  });
  final String title;
  final String description;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: PlayraSpace.lg),
    child: PlayraSurface(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(PlayraSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: PlayraSpace.sm),
            Text(description, style: Theme.of(context).textTheme.bodyMedium),
            if (child != null) ...[
              const SizedBox(height: PlayraSpace.lg),
              child!,
            ],
          ],
        ),
      ),
    ),
  );
}
