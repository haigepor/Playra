import 'package:flutter/material.dart';

import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';
import 'package:kazumi/presentation/modern/secondary/utility_page_art.dart';

class SyncPageBody extends StatelessWidget {
  const SyncPageBody({super.key, required this.children, this.maxWidth = 880});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // 表单调用方的640/720宽度需要保留，服务总览最多760。
            maxWidth: ModernSettingsScope.isActiveOf(context)
                ? maxWidth.clamp(0.0, 760.0).toDouble()
                : maxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: ModernSettingsScope.isActiveOf(context) ? 16 : 20,
            children: children,
          ),
        ),
      ),
    ),
  );
}

class SyncPageIntro extends StatelessWidget {
  const SyncPageIntro({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.artwork,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? artwork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modern = ModernSettingsScope.isActiveOf(context);
    if (artwork != null) {
      return UtilityPageIntro(
        icon: UtilityIconKind.synchronization,
        title: title,
        description: description,
        artwork: artwork,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const UtilitySvgIcon(
              UtilityIconKind.synchronization,
              size: 22,
            ),
          ),
          SizedBox(width: modern ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: modern
                        ? theme.textTheme.titleLarge
                        : theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style:
                      (modern
                              ? theme.textTheme.bodySmall
                              : theme.textTheme.bodyMedium)
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SyncFeedback extends StatelessWidget {
  const SyncFeedback({
    super.key,
    required this.message,
    this.error = false,
    this.busy = false,
    this.progress,
  });

  final String message;
  final bool error;
  final bool busy;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: error ? colors.errorContainer : colors.secondaryContainer,
          borderRadius: BorderRadius.circular(
            ModernSettingsScope.isActiveOf(context) ? 16 : 20,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UtilitySvgIcon(
                  error
                      ? UtilityIconKind.failed
                      : busy
                      ? UtilityIconKind.synchronization
                      : UtilityIconKind.completed,
                  size: 20,
                  color: error
                      ? colors.onErrorContainer
                      : colors.onSecondaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: error
                          ? colors.onErrorContainer
                          : colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
            ],
          ],
        ),
      ),
    );
  }
}
