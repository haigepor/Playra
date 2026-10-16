import 'package:flutter/foundation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/source/content_search.dart'
    show contentTitleKey, ContentGroup;
import 'package:kazumi/services/source/lumina/lumina_models.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'modern_home_controller.dart';

/// 首页展示快照不承担作品身份转换；点击始终交回原始资料或 SDK 入口。
class HomeAnimeCard {
  const HomeAnimeCard({
    required this.id,
    required this.title,
    required this.cover,
    required this.onTap,
    this.ratingScore = 0,
    this.status = '',
    this.subtitle = '',
    this.year,
    this.metadata,
    this.group = ContentGroup.anime,
  });
  factory HomeAnimeCard.metadata(
    BangumiItem item,
    ModernHomeController controller,
    VoidCallback onTap,
  ) => HomeAnimeCard(
    id: '${item.id}',
    title: item.nameCn.isEmpty ? item.name : item.nameCn,
    cover: ['large', 'common', 'medium', 'small']
        .map((size) => item.images[size] ?? '')
        .firstWhere((url) => url.isNotEmpty, orElse: () => ''),
    onTap: onTap,
    ratingScore: item.ratingScore,
    status: controller.scheduleLabel(item),
    subtitle: {
      ...item.metaTags,
      ...item.tags.map((tag) => tag.name),
    }.take(2).join(' · '),
    year: DateTime.tryParse(item.airDate)?.year,
    metadata: item,
  );
  factory HomeAnimeCard.lumina(LuminaVideo video, VoidCallback onTap) =>
      HomeAnimeCard(
        id: 'lumina:${video.id}',
        title: video.title,
        cover: video.cover,
        onTap: onTap,
        status: video.updateLabel,
        subtitle: [
          video.year,
          video.area,
        ].where((value) => value.isNotEmpty).join(' · '),
        year: int.tryParse(video.year),
      );
  final String id, title, cover, status, subtitle;
  final double ratingScore;
  final int? year;
  final BangumiItem? metadata;
  final VoidCallback onTap;
  final ContentGroup group;
  factory HomeAnimeCard.mio(MioVideo video, VoidCallback onTap) =>
      HomeAnimeCard(
        id: video.identity,
        title: video.title,
        cover: video.cover,
        onTap: onTap,
        ratingScore: video.score,
        subtitle: video.subtitle,
        status: video.kind == MioKind.series && video.episodeCount > 0
            ? '更新至 ${video.episodeCount} 集'
            : video.categoryName,
        year: int.tryParse(video.year),
        group: video.kind == MioKind.series
            ? ContentGroup.series
            : ContentGroup.screen,
      );
}

/// 综合推荐按内容类型保留位置，避免动漫列表较长时把已成功的影视挤出首屏。
List<HomeAnimeCard> mixHomeContent(
  List<HomeAnimeCard> anime,
  List<HomeAnimeCard> screen, {
  int? limit,
}) {
  final result = <HomeAnimeCard>[], seen = <String>{};
  final groups = [
    anime.where((card) => card.group == ContentGroup.anime).toList(),
    screen
        .where(
          (card) =>
              card.group == ContentGroup.screen ||
              card.group == ContentGroup.series,
        )
        .toList(),
  ];
  final longest = groups.fold<int>(
    0,
    (value, pool) => pool.length > value ? pool.length : value,
  );
  for (var index = 0; index < longest; index++) {
    for (final pool in groups) {
      if (index < pool.length && seen.add(pool[index].id)) {
        result.add(pool[index]);
      }
      if (limit != null && result.length >= limit) return result;
    }
  }
  return result;
}

/// 仅以完整片名和相同年份抑制重复展示，不把弱同名变成跨 SDK 身份映射。
List<HomeAnimeCard> mergeHomeAnimeCards(
  List<HomeAnimeCard> preferred,
  List<HomeAnimeCard> legacy,
) => [
  ...preferred,
  for (final card in legacy)
    if (!preferred.any(
      (source) =>
          source.year != null &&
          source.year == card.year &&
          contentTitleKey(source.title) == contentTitleKey(card.title),
    ))
      card,
];
