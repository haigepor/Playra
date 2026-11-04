import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/presentation/widgets/playra_card.dart';

/// 旧入口保留明确说明，不再启动已移除来源的控制器。
class SourceUnavailablePage extends StatelessWidget {
  const SourceUnavailablePage({super.key, required this.feature});
  final String feature;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(feature)),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: PlayraLayout.actionSheetWidth,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PlayraSpace.xl),
            child: PlayraCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.layers_clear_outlined, size: 40),
                  const SizedBox(height: PlayraSpace.lg),
                  Text(
                    '当前仅保留 Lumina 数据源',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: PlayraSpace.sm),
                  Text(
                    '$feature所需的数据源已移除。本地历史、收藏和下载记录继续保留。',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
