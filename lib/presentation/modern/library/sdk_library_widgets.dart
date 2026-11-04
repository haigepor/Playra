import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_card.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/services/platform/lumina_support.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'package:kazumi/services/source/lumina/lumina_playback_provider.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/sdk_playback_provider.dart';
import 'package:kazumi/services/source/whisklet/whisklet_catalog.dart';
import 'package:kazumi/services/source/whisklet/whisklet_playback_provider.dart';
import 'package:kazumi/services/storage/sdk_library_store.dart';

/// 个人库卡片打开时按来源现建供给方；第二内容源复用同一实例，避免每次进页
/// 都新建 HTTP 连接池（该 provider 由进程持有，不做逐页释放）。
WhiskletPlaybackProvider? _whiskletLibraryProvider;
SdkPlaybackProvider _whiskletProvider() =>
    _whiskletLibraryProvider ??= WhiskletPlaybackProvider(WhiskletCatalog());

void openSdkLibraryRecord(BuildContext context, SdkLibraryRecord record) {
  // 只允许登记的平台SDK；历史记录不能指定任意模块或绕过平台限制。
  final SdkPlaybackProvider? provider = switch (record.providerId) {
    'lumina' when luminaSupported => LuminaPlaybackProvider(LuminaService()),
    // 第二内容源不依赖 Lumina 平台支持，自己就是完整播放链路。
    'whisklet' => _whiskletProvider(),
    _ => null,
  };
  if (provider == null) {
    KazumiDialog.showToast(context: context, message: '当前平台暂不支持此来源，记录已保留');
    return;
  }
  context.pushNamed(
    '/info/',
    arguments: SdkPlaybackEntry(
      title: record.title,
      cover: record.cover,
      sources: [
        SdkSourceBinding(provider: provider, contentId: record.contentId),
      ],
    ),
  );
}

/// 个人库共享卡片沿用新版surface/outline/字体；历史与收藏操作彼此独立。
class SdkLibraryTile extends StatelessWidget {
  const SdkLibraryTile({
    super.key,
    required this.record,
    required this.onOpen,
    this.onCollect,
    this.onDelete,
    this.compact = false,
  });
  final SdkLibraryRecord record;
  final VoidCallback onOpen;
  final Future<void> Function(int)? onCollect;
  final Future<void> Function()? onDelete;
  final bool compact;
  Future<void> _mutate(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted)
        KazumiDialog.showToast(context: context, message: '保存失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label:
          '${compact ? '继续观看 ' : ''}${record.title}，${record.progressLabel}，${record.sourceName}',
      child: PlayraCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(PlayraSpace.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                NetworkImgLayer(
                  src: record.cover,
                  width: compact ? 44 : 64,
                  height: compact ? 66 : 96,
                  type: 'bg',
                  borderRadius: BorderRadius.circular(PlayraRadius.thumbnail),
                ),
                const SizedBox(width: PlayraSpace.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.title,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: PlayraSpace.xs),
                      Text(
                        record.progressLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: colors.primary),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: PlayraSpace.xs),
                        Text(
                          '${record.sourceName}${record.collectionType > 0 ? ' · ${CollectType.fromValue(record.collectionType).label}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (onCollect != null || onDelete != null)
                  PlayraPopupMenu<int>(
                    tooltip: '管理${record.title}',
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                    onSelected: (value) => unawaited(
                      _mutate(
                        context,
                        () => value == -1 ? onDelete!() : onCollect!(value),
                      ),
                    ),
                    itemBuilder: (_) => [
                      if (onCollect != null)
                        for (final type in CollectType.values)
                          PopupMenuItem(
                            value: type.value,
                            child: Text(
                              type == CollectType.none ? '取消收藏' : type.label,
                            ),
                          ),
                      if (onDelete != null)
                        const PopupMenuItem(value: -1, child: Text('删除观看记录')),
                    ],
                  )
                else
                  Icon(
                    Icons.play_arrow_rounded,
                    color: colors.primary,
                    size: 24,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
