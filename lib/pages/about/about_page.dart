import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kazumi/app_brand.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/content_section.dart';
import 'package:kazumi/pages/about/about_widgets.dart';
import 'package:kazumi/request/config/api_endpoints.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.onCheckUpdate});
  final Future<bool> Function() onCheckUpdate;

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('关于 Playra'),
    body: AboutContent(
      children: [
        _BrandHeader(onCheckUpdate: onCheckUpdate),
        const SizedBox(height: 24),
        ContentSection.group(
          title: '了解应用',
          children: const [
            AboutLinkTile.route(
              icon: Icons.help_outline_rounded,
              title: '使用帮助',
              subtitle: '发现内容、选集播放与数据管理',
              route: '/settings/about/help',
            ),
            AboutLinkTile.route(
              icon: Icons.shield_outlined,
              title: '隐私说明',
              subtitle: '了解本地记录与联网功能',
              route: '/settings/about/privacy',
            ),
          ],
        ),
      ],
    ),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.onCheckUpdate});
  final Future<bool> Function() onCheckUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.outlineVariant.withValues(alpha: .5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: -22,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: .32,
                  child: SvgPicture.asset(
                    'assets/images/modern-about-orbit.svg',
                    width: 210,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.play_circle_outline_rounded,
                  color: c.primary,
                  size: 34,
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    AppBrand.name,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '版本 ${ApiEndpoints.version}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: c.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Text('好故事，随时继续。', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '发现电影与番剧，留住每一次观看。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: c.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [CheckUpdateButton(onCheckUpdate: onCheckUpdate)],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
