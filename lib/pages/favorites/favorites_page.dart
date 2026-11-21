import 'package:kazumi/presentation/widgets/playra_page_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';
import 'package:kazumi/pages/discover/media_widgets.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_backdrop.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 追番（收藏）页面。
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key, required this.onDiscover});
  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayoutMetrics.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PlayraBackdrop(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
              child: ValueListenableBuilder<Box<dynamic>>(
                valueListenable: FavoriteStorage.listenable(),
                builder: (context, box, child) {
                  final favorites = FavoriteStorage.getAll();
                  return Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          layout.gutter,
                          6,
                          layout.gutter,
                          4,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '追番',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontSize: PlayraType.pageTitle,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            if (favorites.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  '${favorites.length} 部',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            const Spacer(),
                            if (favorites.isNotEmpty)
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 44),
                                  padding: EdgeInsets.zero,
                                  alignment: Alignment.centerRight,
                                ),
                                onPressed: () => _manageFavorites(context),
                                child: const Text('管理'),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: favorites.isEmpty
                            ? PlayraPageState(
                                icon: Icons.video_library_outlined,
                                title: '还没有追番',
                                action: FilledButton(
                                  onPressed: onDiscover,
                                  child: const Text('去发现'),
                                ),
                              )
                            : _FavoritesGrid(
                                layout: layout,
                                favorites: favorites,
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _manageFavorites(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheet).height * .75,
          ),
          child: ValueListenableBuilder<Box<dynamic>>(
            valueListenable: FavoriteStorage.listenable(),
            builder: (_, box, child) {
              final records = FavoriteStorage.getAll();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '管理追番',
                            style: Theme.of(sheet).textTheme.titleMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: records.isEmpty
                              ? null
                              : () async {
                                  final confirmed = await showDialog<bool>(
                                    context: sheet,
                                    builder: (dialog) => AlertDialog(
                                      scrollable: true,
                                      insetPadding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 24,
                                      ),
                                      titleTextStyle: Theme.of(dialog)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                      title: const Text('清空全部追番？'),
                                      content: const Text('清空后无法恢复。'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialog, false),
                                          child: const Text('取消'),
                                        ),
                                        PlayraButton.destructive(
                                          onPressed: () =>
                                              Navigator.pop(dialog, true),
                                          child: const Text('清空'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true) return;
                                  await FavoriteStorage.clearAll();
                                  if (sheet.mounted &&
                                      ModalRoute.of(sheet)?.isCurrent == true) {
                                    Navigator.pop(sheet);
                                  }
                                },
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: records.length,
                      itemBuilder: (_, index) {
                        final record = records[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 16,
                            right: 4,
                          ),
                          horizontalTitleGap: 10,
                          minVerticalPadding: 4,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              width: 36,
                              height: 48,
                              child: MediaCoverImage(url: record.cover),
                            ),
                          ),
                          title: Text(
                            record.title,
                            style: Theme.of(sheet).textTheme.bodyMedium,
                          ),
                          subtitle:
                              record.subtitle.isEmpty ||
                                  record.subtitle == record.title
                              ? null
                              : Text(
                                  record.subtitle,
                                  style: Theme.of(sheet).textTheme.bodySmall,
                                ),
                          trailing: IconButton(
                            tooltip: '移除${record.title}',
                            icon: const Icon(
                              Icons.bookmark_remove_outlined,
                              size: 20,
                            ),
                            onPressed: () async {
                              await FavoriteStorage.remove(
                                record.sourceId,
                                record.mediaId,
                              );
                              if (sheet.mounted &&
                                  ModalRoute.of(sheet)?.isCurrent == true &&
                                  FavoriteStorage.getAll().isEmpty) {
                                Navigator.pop(sheet);
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FavoritesGrid extends StatelessWidget {
  const _FavoritesGrid({required this.layout, required this.favorites});

  final HomeLayoutMetrics layout;
  final List<FavoriteRecord> favorites;

  @override
  Widget build(BuildContext context) {
    final items = favorites.map((fav) {
      return MediaItem(
        key: MediaKey(sourceId: fav.sourceId, mediaId: fav.mediaId),
        title: fav.title,
        cover: fav.cover,
        category: fav.category,
        subtitle: fav.subtitle,
      );
    }).toList();

    return CustomScrollView(
      slivers: [
        MediaPosterGrid(
          items: items,
          phoneColumns: 2,
          onTap: (item) {
            context.pushNamed('/detail', arguments: item.key);
          },
          insets: EdgeInsets.fromLTRB(
            layout.gutter,
            0,
            layout.gutter,
            PlayraSpace.md,
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.paddingOf(context).bottom + PlayraSpace.lg,
          ),
        ),
      ],
    );
  }
}
