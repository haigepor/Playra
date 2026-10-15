import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import '../miomedia/miomedia_playing_mark.dart';

Future<T?> showModernPlayerSheet<T>(BuildContext context, Widget child) {
  final media = MediaQuery.of(context);
  final usable =
      media.size.height - media.padding.vertical - media.viewInsets.bottom;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    constraints: BoxConstraints(maxWidth: math.min(media.size.width, 640)),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: media.disableAnimations
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: Duration(milliseconds: 220),
            reverseDuration: Duration(milliseconds: 180),
          ),
    builder: (_) => SafeArea(
      top: false,
      child: SizedBox(height: usable * .8, child: child),
    ),
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
            IconButton(
              tooltip: '关闭',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
    final c = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      label: playing ? '$title，正在播放' : null,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(60, 48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          foregroundColor: selected ? c.primary : c.onSurfaceVariant,
          backgroundColor: selected
              ? c.secondaryContainer
              : c.surfaceContainerLow,
          side: BorderSide(
            color: selected
                ? c.primary.withValues(alpha: .5)
                : Colors.transparent,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected) ...[
              MioPlayingMark(active: playing, color: c.primary),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (downloaded) ...[
              const SizedBox(width: 4),
              const Icon(LucideIcons.download, size: 12),
            ],
          ],
        ),
      ),
    );
  }
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
        const PlayerSheetHeader(title: '全部剧集'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(
                child: Text('点击剧集，自动匹配播放来源', style: TextStyle(fontSize: 12)),
              ),
              TextButton.icon(
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
              TextButton.icon(
                onPressed: () => setState(() => descending = !descending),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(LucideIcons.arrowDownUp, size: 16),
                label: Text(descending ? '降序' : '升序'),
              ),
              TextButton.icon(
                onPressed: locate,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
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
              itemBuilder: (_, i) => TextButton(
                onPressed: () {
                  setState(() => segment = i);
                  if (scroll.hasClients) scroll.jumpTo(0);
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(64, 48),
                  backgroundColor: i == segment ? c.secondaryContainer : null,
                ),
                child: Text('${i * 50 + 1}–${math.min((i + 1) * 50, count)}'),
              ),
            ),
          ),
        const Divider(height: 1),
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
