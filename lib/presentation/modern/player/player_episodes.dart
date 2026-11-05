import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/widgets/playra_sheet.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import '../player/playing_mark.dart';

Future<T?> showModernPlayerSheet<T>(BuildContext context, Widget child) {
  return showPlayraSheet<T>(
    context: context,
    size: PlayraSheetSize.standard,
    builder: (_) => child,
  );
}

class PlayerSheetHeader extends StatelessWidget {
  const PlayerSheetHeader({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 10),
      Container(
        width: 30,
        height: 3,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            PlayraIconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(LucideIcons.x, size: 20),
            ),
          ],
        ),
      ),
    ],
  );
}

class PlayerEpisodeButton extends StatelessWidget {
  const PlayerEpisodeButton({
    super.key,
    required this.title,
    required this.onTap,
    this.selected = false,
    this.playing = false,
    this.downloaded = false,
  });
  final String title;
  final VoidCallback onTap;
  final bool selected, playing, downloaded;
  @override
  Widget build(BuildContext context) {
    final tokens = PlayraTokens.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(PlayraRadius.thumbnail),
      side: BorderSide(
        color: selected ? tokens.primary : tokens.borderSubtle,
      ),
    );
    return Semantics(
      selected: selected,
      label: playing ? '$title，正在播放' : null,
      child: Material(
        color: selected ? tokens.primaryContainer : tokens.surfaceRaised,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Container(
            constraints: const BoxConstraints(minWidth: 60, minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  PlayingMark(active: playing, color: tokens.primary),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? tokens.primary : tokens.foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (downloaded) ...[
                  const SizedBox(width: 4),
                  Icon(LucideIcons.download, size: 12, color: tokens.foregroundSubtle),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 资料集数与线路收录集数含义不同，不能在匹配前承诺目录条目均可播放。
class PlayerEpisodesHeader extends StatelessWidget {
  const PlayerEpisodesHeader({
    super.key,
    required this.count,
    required this.sourceVerified,
    required this.onShowAll,
  });

  final int count;
  final bool sourceVerified;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              sourceVerified ? '选集' : '资料目录',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Flexible(
            child: PlayraButton.ghost(
              onPressed: onShowAll,
              child: Text(
                sourceVerified ? '当前线路 $count 集 · 全部 ›' : '目录 $count 集 ›',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      if (!sourceVerified)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '实际可播放集数以匹配来源为准',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ],
  );
}

/// 未选源时展示资料目录，返回真实分集对象，自动匹配只使用正片集号。
class PlayerCatalogEpisodesSheet extends StatefulWidget {
  const PlayerCatalogEpisodesSheet({
    super.key,
    required this.episodes,
    this.selectedId,
  });
  final List<EpisodeInfo> episodes;
  final int? selectedId;
  @override
  State<PlayerCatalogEpisodesSheet> createState() =>
      _PlayerCatalogEpisodesSheetState();
}

class _PlayerCatalogEpisodesSheetState
    extends State<PlayerCatalogEpisodesSheet> {
  bool descending = false;
  late int segment =
      math.max(
        0,
        widget.episodes.indexWhere((e) => e.id == widget.selectedId),
      ) ~/
      50;
  @override
  Widget build(BuildContext context) {
    final episodes = [...widget.episodes]
      ..sort((a, b) => a.episode.compareTo(b.episode));
    final segments = (episodes.length + 49) ~/ 50;
    final visible = episodes.skip(segment * 50).take(50).toList();
    if (descending) visible.sort((a, b) => b.episode.compareTo(a.episode));
    return Column(
      children: [
        const PlayerSheetHeader(title: '资料目录'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(
                child: Text('实际可播放集数以匹配来源为准', style: TextStyle(fontSize: 12)),
              ),
              PlayraButton.ghostIcon(
                onPressed: () => setState(() => descending = !descending),
                icon: Icon(
                  descending ? LucideIcons.arrowDown : LucideIcons.arrowUp,
                  size: 16,
                ),
                label: Text(descending ? '降序' : '升序'),
              ),
            ],
          ),
        ),
        if (segments > 1)
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: segments,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ChoiceChip(
                label: Text(
                  '${episodes[i * 50].episode.toInt()}–${episodes[math.min((i + 1) * 50, episodes.length) - 1].episode.toInt()}',
                ),
                selected: segment == i,
                onSelected: (_) => setState(() => segment = i),
              ),
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 112,
              mainAxisExtent: 56,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: visible.length,
            itemBuilder: (_, i) {
              final episode = visible[i];
              return PlayerEpisodeButton(
                title: '第${episode.episode.toInt()}集',
                selected: episode.id == widget.selectedId,
                onTap: () => Navigator.pop(context, episode),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 排序和分段只修改视图；返回的路/集始终是来源的原始索引。
class PlayerEpisodesSheet extends StatefulWidget {
  const PlayerEpisodesSheet({
    super.key,
    required this.roads,
    required this.selected,
    this.playing,
    this.sourceName = '',
    this.confirmSource = false,
    this.showRoadSelector = true,
    this.downloadedUrls = const {},
  });
  final List<Road> roads;
  final VideoEpisodeSelection selected;
  final VideoEpisodeSelection? playing;
  final String sourceName;
  final bool confirmSource;
  final bool showRoadSelector;
  final Set<String> downloadedUrls;
  @override
  State<PlayerEpisodesSheet> createState() => _PlayerEpisodesSheetState();
}

class _PlayerEpisodesSheetState extends State<PlayerEpisodesSheet> {
  late int road = widget.selected.road.clamp(
    0,
    math.max(0, widget.roads.length - 1),
  );
  late int segment = (widget.selected.episode - 1) ~/ 50;
  bool descending = false;
  final scroll = ScrollController();
  int columns = 4;
  double extent = 64;
  Road? get data => widget.roads.isEmpty ? null : widget.roads[road];
  int get count =>
      math.min(data?.data.length ?? 0, data?.identifier.length ?? 0);
  List<int> get indices {
    final begin = (segment * 50).clamp(0, count);
    final items = List.generate(math.min(50, count - begin), (i) => begin + i);
    return descending ? items.reversed.toList() : items;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => locate());
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void locate() {
    if (!mounted || widget.roads.isEmpty) return;
    setState(() {
      road = widget.selected.road.clamp(0, widget.roads.length - 1);
      segment = (widget.selected.episode - 1) ~/ 50;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final i = indices.indexOf(widget.selected.episode - 1);
      if (i >= 0) {
        scroll.jumpTo(
          ((i ~/ columns) * (extent + 8)).clamp(
            0,
            scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (segment * 50 >= count) segment = 0;
    final visible = indices;
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayerSheetHeader(title: widget.confirmSource ? '确认目标剧集' : '全部选集'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '${widget.sourceName}${widget.confirmSource ? ' · 选择后从头播放' : ' · 共 $count 集'}',
            style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.showRoadSelector && widget.roads.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: DropdownButton<int>(
                    value: road,
                    isExpanded: true,
                    itemHeight: null,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (var i = 0; i < widget.roads.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              widget.roads[i].name.isEmpty
                                  ? '线路 ${i + 1}'
                                  : widget.roads[i].name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          road = value;
                          segment = 0;
                        });
                        if (scroll.hasClients) scroll.jumpTo(0);
                      }
                    },
                  ),
                ),
              PlayraButton.ghostIcon(
                onPressed: () => setState(() => descending = !descending),
                icon: const Icon(LucideIcons.arrowDownUp, size: 16),
                label: Text(descending ? '降序' : '升序'),
              ),
              PlayraButton.ghostIcon(
                onPressed: locate,
                icon: const Icon(LucideIcons.locateFixed, size: 16),
                label: const Text('当前集'),
              ),
            ],
          ),
        ),
        if (count > 50)
          SizedBox(
            height: 52,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: (count / 50).ceil(),
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => PlayraButton.ghost(
                onPressed: () {
                  setState(() => segment = i);
                  if (scroll.hasClients) scroll.jumpTo(0);
                },
                child: Text('${i * 50 + 1}–${math.min((i + 1) * 50, count)}'),
              ),
            ),
          ),
        const PlayraDivider(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
              columns = ((constraints.maxWidth - 32) / (78 * scale))
                  .floor()
                  .clamp(1, 4);
              extent = math.max(60, 48 * scale);
              if (visible.isEmpty) {
                return const Center(child: Text('这条线路暂无可用剧集'));
              }
              return GridView.builder(
                controller: scroll,
                padding: const EdgeInsets.all(16),
                itemCount: visible.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: extent,
                ),
                itemBuilder: (_, index) {
                  final original = visible[index];
                  final selection = VideoEpisodeSelection(
                    episode: original + 1,
                    road: road,
                  );
                  return PlayerEpisodeButton(
                    title: data!.identifier[original],
                    selected: selection == widget.selected,
                    playing: selection == widget.playing,
                    downloaded: widget.downloadedUrls.contains(
                      data!.data[original],
                    ),
                    onTap: () => Navigator.pop(context, selection),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
