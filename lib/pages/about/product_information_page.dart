import 'package:flutter/material.dart';
import 'package:kazumi/app_brand.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/content_section.dart';
import 'package:kazumi/pages/about/about_widgets.dart';

enum ProductInformation { help, privacy, legal }

class ProductInformationPage extends StatelessWidget {
  const ProductInformationPage({super.key, required this.information});
  final ProductInformation information;

  @override
  Widget build(BuildContext context) {
    final (title, paragraphs) = switch (information) {
      ProductInformation.help => (
        '使用帮助',
        <(String, String)>[
          ('发现与播放', '在发现页选择分类或搜索作品，进入详情后点选剧集播放。播放来源的可用性会随服务状态变化，可尝试其他线路或稍后重试。'),
          ('观看记录', '观看历史、收藏与设置保存在当前设备。清除图片缓存不会删除这些记录。卸载应用或清除应用数据会删除本地数据。'),
          (
            '同步与更新',
            'Bangumi 与 WebDAV 同步需自行配置。应用更新从 Playra 的版本发布源获取，也可关闭自动检查并手动更新。',
          ),
        ],
      ),
      ProductInformation.privacy => (
        '隐私说明',
        <(String, String)>[
          ('本地数据', '应用在设备上保存设置、观看记录、收藏、缓存与内容服务设备身份。设备身份用于内容请求与播放凭证，不需要在界面中展示。'),
          ('联网功能', '内容查询、图片、视频、弹幕与版本检查会连接对应服务。服务方会收到完成请求所需的数据及网络地址，适用其自身规则。'),
          (
            '可选同步',
            '启用 Bangumi 或 WebDAV 后，相关账号凭据和同步数据会用于你配置的服务。可在同步设置中管理或关闭。正式版不提供错误日志浏览入口。',
          ),
        ],
      ),
      ProductInformation.legal => (
        '许可与致谢',
        <(String, String)>[
          (
            '应用许可',
            'Playra 基于 Kazumi 开源项目持续开发，沿用 GNU GPL v3.0 许可。原作者版权与第三方组件许可保留。',
          ),
        ],
      ),
    };
    return SettingsDetailScaffold(
      title: Text(title),
      body: AboutContent(
        children: [
          for (final paragraph in paragraphs) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text(
                paragraph.$1,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 24),
              child: Text(
                paragraph.$2,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.8,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (information == ProductInformation.legal)
            ContentSection.group(
              title: '更多信息',
              children: const [
                AboutLinkTile.route(
                  icon: Icons.favorite_outline_rounded,
                  title: '致谢',
                  route: '/settings/about/credits',
                ),
                AboutLinkTile.route(
                  icon: Icons.description_outlined,
                  title: '第三方许可证',
                  route: '/settings/about/license',
                ),
                AboutLinkTile(
                  icon: Icons.balance_rounded,
                  title: 'GNU GPL v3.0',
                  url: '${AppBrand.repositoryUrl}/blob/main/LICENSE',
                ),
              ],
            ),
        ],
      ),
    );
  }
}
