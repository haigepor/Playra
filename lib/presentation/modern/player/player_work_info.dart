import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kazumi/bean/card/character_card.dart';
import 'package:kazumi/bean/card/staff_card.dart';
import 'package:kazumi/modules/bangumi/bangumi_relation.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/services/platform/resource_url.dart';
import 'player_episodes.dart';

class PlayerCover extends StatelessWidget {
  const PlayerCover({super.key, required this.url, this.player = false});
  final String url;
  final bool player;
  Widget get placeholder => SvgPicture.asset(
    'assets/images/modern-player-${player ? 'placeholder' : 'poster-placeholder'}.svg',
    fit: BoxFit.cover,
    excludeFromSemantics: true,
  );
  @override
  Widget build(BuildContext context) => url.isEmpty
      ? placeholder
      : CachedNetworkImage(
          imageUrl: platformResourceUrl(url),
          fit: BoxFit.cover,
          placeholder: (context, _) => LayoutBuilder(
            builder: (context, bounds) => ContentSkeleton(
              child: Bone(
                width: bounds.maxWidth,
                height: bounds.maxHeight,
                uniRadius: 0,
              ),
            ),
          ),
          errorWidget: (_, _, _) => placeholder,
        );
}

class PlayerRelations extends StatelessWidget {
  const PlayerRelations({
    super.key,
    required this.relations,
    this.beforeNavigate,
  });
  final List<BangumiRelation> relations;
  final Future<void> Function()? beforeNavigate;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = MediaQuery.textScalerOf(context).scale(14) > 20 ? 2 : 3;
      final width = (constraints.maxWidth - (count - 1) * 10) / count;
      return Wrap(
        spacing: 10,
        runSpacing: 16,
        children: [
          for (final relation in relations)
            SizedBox(
              width: width,
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () async {
                  await beforeNavigate?.call();
                  if (!context.mounted) return;
                  context.pushNamed(
                    '/info/',
                    arguments: relation.toBangumiItem(),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: AspectRatio(
                        aspectRatio: 5 / 7,
                        child: PlayerCover(
                          url: relation.toBangumiItem().images['large'] ?? '',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      relation.toBangumiItem().nameCn.isEmpty
                          ? relation.toBangumiItem().name
                          : relation.toBangumiItem().nameCn,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      relation.relation,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class PlayerWorkInfoSheet extends StatefulWidget {
  const PlayerWorkInfoSheet({
    super.key,
    required this.controller,
    this.beforeNavigate,
  });
  final InfoController controller;
  final Future<void> Function()? beforeNavigate;
  @override
  State<PlayerWorkInfoSheet> createState() => _PlayerWorkInfoSheetState();
}

class _PlayerWorkInfoSheetState extends State<PlayerWorkInfoSheet>
    with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 4, vsync: this)
    ..addListener(loadSelected);
  final pending = <int, Future<void>>{};
  void loadSelected() {
    final index = tabs.index;
    if (index == 0 || pending.containsKey(index)) return;
    setState(() => pending[index] = load(index));
  }

  Future<void> load(int index) => switch (index) {
    1 => widget.controller.queryBangumiCharactersByID(
      widget.controller.bangumiItem.id,
    ),
    2 => widget.controller.queryBangumiRelationsByID(
      widget.controller.bangumiItem.id,
    ),
    _ => widget.controller.queryBangumiStaffsByID(
      widget.controller.bangumiItem.id,
    ),
  };
  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.controller.bangumiItem;
    return Column(
      children: [
        const PlayerSheetHeader(title: '作品资料'),
        TabBar(
          controller: tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: '简介'),
            Tab(text: '角色'),
            Tab(text: '关联'),
            Tab(text: '制作人员'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: tabs,
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    item.nameCn.isEmpty ? item.name : item.nameCn,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.nameCn.isNotEmpty && item.name != item.nameCn)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        item.name,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SelectableText(
                    item.summary.isEmpty ? '暂无简介' : item.summary,
                    style: const TextStyle(fontSize: 14, height: 1.8),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in item.tags)
                        ActionChip(
                          label: Text(tag.name),
                          onPressed: () => context.pushNamed(
                            '/search/${Uri.encodeComponent(tag.name)}',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              for (var index = 1; index < 4; index++)
                FutureBuilder<void>(
                  future: pending[index],
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: TextButton(
                          onPressed: () =>
                              setState(() => pending[index] = load(index)),
                          child: const Text('资料加载失败，点击重试'),
                        ),
                      );
                    }
                    if (snapshot.connectionState != ConnectionState.done) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: index == 2
                            ? const SkeletonPosters(count: 3)
                            : const SkeletonInfoList(),
                      );
                    }
                    final count = switch (index) {
                      1 => widget.controller.characterList.length,
                      2 => widget.controller.relationList.length,
                      _ => widget.controller.staffList.length,
                    };
                    if (count == 0) return const Center(child: Text('暂无相关资料'));
                    if (index == 2) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: PlayerRelations(
                          relations: widget.controller.relationList.toList(),
                          beforeNavigate: widget.beforeNavigate,
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: count,
                      itemBuilder: (_, i) => index == 1
                          ? CharacterCard(
                              modern: true,
                              characterItem: widget.controller.characterList[i],
                            )
                          : StaffCard(
                              staffFullItem: widget.controller.staffList[i],
                            ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
