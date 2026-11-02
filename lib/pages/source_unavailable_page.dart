import 'package:flutter/material.dart';

/// 旧入口保留明确说明，不再启动已移除来源的控制器。
class SourceUnavailablePage extends StatelessWidget {
  const SourceUnavailablePage({super.key, required this.feature});
  final String feature;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(feature)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_clear_outlined, size: 40),
            const SizedBox(height: 16),
            Text(
              '当前仅保留 Lumina 数据源',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '$feature所需的数据源已移除。本地历史、收藏和下载记录继续保留。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
