import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';

class SdkPoster extends StatelessWidget {
  const SdkPoster({
    super.key,
    required this.video,
    required this.onTap,
    this.rank,
    this.providerName,
    this.identity,
    this.statusLabel,
    this.rankIsSequence = false,
  });
  final SdkVideo video;
  final VoidCallback onTap;
  final int? rank;
  final String? providerName, identity, statusLabel;
  final bool rankIsSequence;
  String get metadata => [
    if (providerName?.isNotEmpty == true) providerName!,
    _metadata(video),
  ].where((text) => text.isNotEmpty).join(' · ');

  @override
  Widget build(BuildContext context) {
    final tokens = PlayraTokens.of(context);
    return Semantics(
      label:
          '${rank == null
              ? ''
              : rankIsSequence
              ? '展示序号$rank，'
              : '第$rank名，'}查看 ${video.title}，$metadata',
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: ValueKey(
          identity == null ? 'sdk-poster-${video.id}' : 'sdk-poster-$identity',
        ),
        borderRadius: BorderRadius.circular(PlayraRadius.poster),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, bounds) => SizedBox(
                width: bounds.maxWidth,
                height: bounds.maxWidth * 1.42,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(PlayraRadius.poster),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetworkImgLayer(
                        src: video.cover.isEmpty ? video.poster : video.cover,
                        width: bounds.maxWidth,
                        height: bounds.maxWidth * 1.42,
                        type: 'bg',
                        borderRadius: BorderRadius.zero,
                      ),
                      const Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 56,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Color(0x80000000),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 保留来源的原始评分；缺失时不制造评分或清晰度标签。
                      if (rank != null ||
                          (video.score.isFinite && video.score > 0))
                        Positioned(
                          top: 0,
                          left: 0,
                          // 名次统一为紧凑数字角标，避免小尺寸奖牌遮挡海报。
                          child: Container(
                            constraints: rank == null
                                ? null
                                : const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 26,
                                  ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.rankGold,
                              borderRadius: const BorderRadius.only(
                                bottomRight: Radius.circular(PlayraRadius.thumbnail),
                              ),
                            ),
                            child: Text(
                              rank == null
                                  ? video.score.toStringAsFixed(1)
                                  : '$rank',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: tokens.warningContainer,
                                fontSize: rank == null ? PlayraType.small : PlayraType.label,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 6,
                        left: 6,
                        right: 6,
                      child: Text(
                        statusLabel ?? '',
                        maxLines: 1,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            video.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            metadata,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
  }
}

String _metadata(SdkVideo video) =>
    [video.year, video.area].where((s) => s.isNotEmpty && s != '0').join(' · ');
