import 'package:kazumi/app_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:kazumi/modules/my/watch_stats.dart';
import 'profile_sync_state.dart';
import '../widgets/modern_page_art.dart';

class ModernProfileView extends StatelessWidget {
  const ModernProfileView({
    super.key,
    required this.stats,
    required this.sync,
    required this.version,
    required this.onOpen,
    required this.onDiscover,
    this.showDeveloperTools = AppBuildPolicy.developerTools,
  });
  final WatchStats stats;
  final ProfileSyncState sync;
  final String version;
  final ValueChanged<String> onOpen;
  final VoidCallback onDiscover;
  final bool showDeveloperTools;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.only(left: 20, right: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '我的',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '全部设置',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: Icon(
                      LucideIcons.settings,
                      size: 20,
                      color: c.onSurfaceVariant,
                    ),
                    onPressed: () => onOpen('/settings/'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              key: const PageStorageKey('modern-profile-scroll'),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _footprint(context),
                        const SizedBox(height: 12),
                        _quickActions(context),
                        _group(context, '观看偏好', [
                          (LucideIcons.palette, '外观设置', '/settings/theme', ''),
                          (
                            LucideIcons.slidersHorizontal,
                            '播放设置',
                            '/settings/player',
                            '',
                          ),
                          (
                            LucideIcons.messageSquare,
                            '弹幕设置',
                            '/settings/danmaku/',
                            '',
                          ),
                          (
                            LucideIcons.layoutGrid,
                            '页面版本',
                            '/settings/interface',
                            '新版 · 预览',
                          ),
                        ]),
                        _group(context, '数据与同步', [
                          (
                            LucideIcons.refreshCw,
                            'Bangumi 追番同步',
                            '/settings/bangumi/',
                            sync.username.isEmpty
                                ? sync.bangumi
                                : '${sync.bangumi}\n${sync.username}',
                          ),
                          (
                            LucideIcons.cloud,
                            'WebDAV 多设备同步',
                            '/settings/webdav/',
                            sync.webDav,
                          ),
                          (
                            LucideIcons.refreshCw,
                            '全部同步设置',
                            '/settings/sync',
                            '',
                          ),
                          (
                            LucideIcons.hardDrive,
                            '存储管理',
                            '/settings/storage',
                            '',
                          ),
                        ]),
                        _group(context, '应用', [
                          (LucideIcons.info, '关于应用', '/settings/about/', ''),
                          if (showDeveloperTools)
                            (
                              LucideIcons.flaskConical,
                              '组件实验室',
                              '/ui/components',
                              '',
                            ),
                        ]),
                        const SizedBox(height: 24),
                        Text(
                          '${AppBrand.name} · $version',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: c.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footprint(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final empty =
        stats.watchedBangumiCount == 0 && stats.watchedEpisodeCount == 0;
    return Container(
      constraints: BoxConstraints(minHeight: empty ? 148 : 176),
      decoration: BoxDecoration(
        color: c.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.outline.withValues(alpha: .5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: empty ? 12 : 0,
            top: empty ? 10 : 0,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: empty ? .45 : .20,
                  child: empty
                      ? SvgPicture.asset(
                          'assets/images/modern-profile-empty.svg',
                          width: 80,
                        )
                      : const ModernMaterialArt(
                          asset: 'modern-profile-header-art.png',
                          width: 480,
                          opacity: 1,
                        ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(right: empty ? 72 : 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        empty ? '你的观看足迹，从这里开始' : '观看足迹',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        empty ? '观看后，记录会保存在这里' : '每一段故事，都有迹可循',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _stat(
                        context,
                        stats.watchedBangumiCount,
                        '有观看记录的番剧',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _stat(
                        context,
                        stats.watchedEpisodeCount,
                        '记录过的集数',
                      ),
                    ),
                  ],
                ),
                if (empty)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(48, 44),
                    ),
                    onPressed: onDiscover,
                    child: const Text('去发现番剧', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, int count, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        label: '$label：$count',
        excludeSemantics: true,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '$count',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    ],
  );

  Widget _quickActions(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final vertical =
          constraints.maxWidth < 340 &&
          MediaQuery.textScalerOf(context).scale(14) > 18;
      final items = [
        (
          LucideIcons.history,
          '历史记录',
          stats.watchedBangumiCount == 0 ? '暂无观看记录' : '回到上次观看',
          '/settings/history/',
        ),
        (
          LucideIcons.download,
          '离线缓存',
          stats.downloadTaskCount == 0
              ? '管理离线内容'
              : '${stats.downloadTaskCount} 集任务',
          '/settings/download/',
        ),
        (LucideIcons.puzzle, '播放规则', '管理播放来源', '/settings/plugin/'),
      ];
      final children = items.map((item) {
        final c = Theme.of(context).colorScheme;
        final icon = Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(item.$1, size: 22, color: c.primary),
        );
        final copy = Column(
          crossAxisAlignment: vertical
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Text(
              item.$2,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: vertical ? TextAlign.left : TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              item.$3,
              style: TextStyle(
                fontSize: 10,
                height: 1.5,
                color: c.onSurfaceVariant,
              ),
              textAlign: vertical ? TextAlign.left : TextAlign.center,
            ),
          ],
        );
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onOpen(item.$4),
            child: Container(
              constraints: BoxConstraints(minHeight: vertical ? 64 : 88),
              padding: EdgeInsets.symmetric(
                vertical: 8,
                horizontal: vertical ? 12 : 0,
              ),
              child: vertical
                  ? Row(
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        Expanded(child: copy),
                        Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: c.onSurfaceVariant,
                        ),
                      ],
                    )
                  : Column(children: [icon, const SizedBox(height: 6), copy]),
            ),
          ),
        );
      }).toList();
      return vertical
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: children[i]),
                ],
              ],
            );
    },
  );

  Widget _group(
    BuildContext context,
    String title,
    List<(IconData, String, String, String)> items,
  ) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.onSurfaceVariant,
              ),
            ),
          ),
          Material(
            color: c.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: c.outline.withValues(alpha: .5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 46,
                      endIndent: 14,
                      color: c.outline.withValues(alpha: .4),
                    ),
                  InkWell(
                    onTap: () => onOpen(items[i].$3),
                    child: Container(
                      constraints: BoxConstraints(
                        minHeight: items[i].$4.isEmpty ? 56 : 68,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            items[i].$1,
                            size: 20,
                            color: c.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  items[i].$2,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                if (items[i].$4.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    items[i].$4,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: c.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: c.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
