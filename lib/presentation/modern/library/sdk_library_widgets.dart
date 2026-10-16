import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/services/platform/lumina_support.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'package:kazumi/services/source/lumina/lumina_playback_provider.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/source/miomedia/miomedia_playback_provider.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/sdk_playback_provider.dart';
import 'package:kazumi/services/storage/sdk_library_store.dart';

void openSdkLibraryRecord(BuildContext context, SdkLibraryRecord record) {
  // 只允许登记的平台SDK；历史记录不能指定任意模块或绕过平台限制。
  final SdkPlaybackProvider? provider = switch (record.providerId) {
    'lumina' when luminaSupported => LuminaPlaybackProvider(LuminaService()),
    'miomedia' => MioSdkPlaybackProvider(MioMediaService()),
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
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                NetworkImgLayer(
                  src: record.cover,
                  width: compact ? 44 : 64,
                  height: compact ? 66 : 96,
                  type: 'bg',
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(width: 12),
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
                      const SizedBox(height: 4),
                      Text(
                        record.progressLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: colors.primary),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 4),
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
                  PopupMenuButton<int>(
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
