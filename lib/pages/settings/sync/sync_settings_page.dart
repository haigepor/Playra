import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';

import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/presentation/modern/secondary/utility_page_art.dart';
import 'package:kazumi/pages/settings/sync/sync_settings_widgets.dart';
import 'package:kazumi/services/storage/storage.dart';

enum _SyncStatus {
  unconfigured('未配置', Icons.settings_outlined),
  connectionError('连接异常', Icons.error_outline_rounded),
  enabled('已开启', Icons.check_circle_outline_rounded),
  disabled('已关闭', Icons.pause_circle_outline_rounded),
  contentRequired('待选择内容', Icons.tune_rounded);

  const _SyncStatus(this.label, this.icon);

  final String label;
  final IconData icon;
}

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  Future<void> _open(String route) async {
    await context.pushNamed(route);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('同步设置'),
    body: Builder(
      builder: (context) {
        final hasServer = GStorage.getSetting(
          SettingsKeys.webDavURL,
        ).trim().isNotEmpty;
        final webDavEnabled = GStorage.getSetting(SettingsKeys.webDavEnable);
        final hasSyncContent =
            GStorage.getSetting(SettingsKeys.webDavEnableHistory) ||
            GStorage.getSetting(SettingsKeys.webDavEnableCollect) ||
            GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield);
        final colors = Theme.of(context).colorScheme;
        final cards = [
          _SyncServiceCard(
            title: '多设备同步',
            service: 'WebDAV',
            description: '通过自己的云盘，在其他设备接着看。',
            content: '观看记录 · 收藏 · 弹幕屏蔽词',
            icon: Icons.devices_rounded,
            color: colors.tertiaryContainer,
            onColor: colors.onTertiaryContainer,
            status: !hasServer
                ? _SyncStatus.unconfigured
                : webDavEnabled
                ? hasSyncContent
                      ? _SyncStatus.enabled
                      : _SyncStatus.contentRequired
                : _SyncStatus.disabled,
            action: hasServer ? '管理多设备同步' : '设置 WebDAV',
            onPressed: () => _open('/settings/webdav/'),
          ),
        ];
        return SyncPageBody(
          children: [
            const SyncPageIntro(
              icon: Icons.sync_rounded,
              title: '让追番保持同步',
              description: '使用自己的 WebDAV 保存个人记录。',
              artwork: 'modern-sync-art',
            ),
            ...cards,
          ],
        );
      },
    ),
  );
}

class _SyncServiceCard extends StatelessWidget {
  const _SyncServiceCard({
    required this.title,
    required this.service,
    required this.description,
    required this.content,
    required this.icon,
    required this.color,
    required this.onColor,
    required this.status,
    required this.action,
    required this.onPressed,
  });

  final String title;
  final String service;
  final String description;
  final String content;
  final IconData icon;
  final Color color;
  final Color onColor;
  final _SyncStatus status;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modern = ModernSettingsScope.isActiveOf(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(modern ? PlayraSpace.lg : PlayraSpace.xxl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(PlayraRadius.control),
                ),
                child: UtilitySvgIcon(
                  service == 'Bangumi'
                      ? UtilityIconKind.collection
                      : UtilityIconKind.devices,
                  size: 22,
                  color: onColor,
                ),
              ),
              const SizedBox(width: PlayraSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        service,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: _SyncStatusChip(status: status),
          ),
          const SizedBox(height: PlayraSpace.md),
          Text(
            description,
            style: modern
                ? theme.textTheme.bodySmall
                : theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: PlayraSpace.lg),
          Text(
            content,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: modern ? 16 : 24),
          PlayraButton.tonalIcon(
            onPressed: onPressed,
            label: Text(action),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusChip extends StatelessWidget {
  const _SyncStatusChip({required this.status});

  final _SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      _SyncStatus.connectionError => (
        colors.errorContainer,
        colors.onErrorContainer,
      ),
      _SyncStatus.enabled => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      _ => (colors.surfaceContainerHighest, colors.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PlayraSpace.md,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 16, color: foreground),
          const SizedBox(width: PlayraSpace.compact),
          Flexible(
            child: Text(
              status.label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
