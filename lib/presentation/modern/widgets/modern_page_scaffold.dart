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
        IconButton(
          tooltip: '页面样式',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => context.pushNamed('/settings/interface'),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description, style: Theme.of(context).textTheme.bodyMedium),
            if (child != null) ...[const SizedBox(height: 16), child!],
          ],
        ),
      ),
    ),
  );
}
