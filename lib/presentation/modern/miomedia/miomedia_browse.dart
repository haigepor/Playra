import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/widget/content_skeleton.dart';
import 'package:flutter/gestures.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';
import '../home/home_theme.dart';
import '../home/modern_home_controller.dart';
import '../settings/modern_back_button.dart';
import '../widgets/modern_section_mark.dart';
import '../widgets/near_end_scroll.dart';
import 'miomedia_home_controller.dart';

class MioHomeSections extends StatelessWidget {
  const MioHomeSections({
    super.key,
    required this.controller,
    required this.feed,
    required this.onDetails,
  });
  final MioHomeController controller;
  final HomeFeed feed;
  final ValueChanged<MioVideo> onDetails;
  @override
  Widget build(BuildContext context) {
    final selected = switch (feed) {
      HomeFeed.movies => MioKind.movie,
      HomeFeed.television => MioKind.series,
      HomeFeed.variety => MioKind.variety,
      HomeFeed.comicDrama => MioKind.comicDrama,
      _ => null,
    };
    final kinds = feed == HomeFeed.screen
        ? [MioKind.movie, MioKind.variety]
        : selected == null
        ? MioHomeController.kinds
        : [selected];
    return Column(
      children: [
        for (final kind in kinds)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const ModernSectionMark(kind: ModernSectionKind.curated),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kind.label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MioBrowsePage(
                            service: controller.service,
                            kind: kind,
                            categoryId: controller.categoryIds[kind],
                            onDetails: onDetails,
                          ),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                        padding: const EdgeInsets.only(left: 8),
                        minimumSize: const Size(48, 48),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('查看更多', style: TextStyle(fontSize: 11)),
                          SizedBox(width: 4),
                          Icon(LucideIcons.chevronRight, size: 14),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if ((controller.items[kind] ?? []).isEmpty &&
                    (controller.loading.contains(kind) ||
                        controller.discovering))
                  LayoutBuilder(
                    builder: (context, bounds) => SkeletonPosters(
                      horizontal: selected == null,
                      gridDelegate: selected == null
                          ? null
                          : mioPosterGridDelegate(context, bounds.maxWidth),
                      count: selected == null ? 4 : 6,
                      infoExtent: 66,
                    ),
                  )
                else if ((controller.items[kind] ?? []).isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            controller.discoveryFailed ||
                                    controller.failed.contains(kind)
                                ? controller.failureMessage(kind)
                                : controller.discovering
                                ? '正在加载${kind.label}'
                                : '暂无${kind.label}内容',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (controller.discoveryFailed ||
                            controller.failed.contains(kind))
                          TextButton(
                            onPressed: () =>
                                controller.categoryIds.containsKey(kind)
                                ? controller.load(kind, reset: true)
                                : controller.bootstrap(force: true),
                            child: const Text('重试'),
                          ),
                      ],
                    ),
                  )
                else if (selected != null) ...[
                  MioPosterGrid(
                    items: controller.items[kind]!,
                    onDetails: onDetails,
                  ),
                  if (controller.loading.contains(kind))
                    LayoutBuilder(
                      builder: (context, bounds) => SkeletonPosters(
                        horizontal: false,
                        count: 3,
                        gridDelegate: mioPosterGridDelegate(
                          context,
                          bounds.maxWidth,
                        ),
                      ),
                    ),
                  Center(
                    child: TextButton(
                      key: ValueKey('mio-load-more-${kind.name}'),
                      onPressed: controller.loading.contains(kind)
                          ? null
                          : controller.failed.contains(kind)
                          ? () => controller.load(
                              kind,
                              reset: !controller.pages.containsKey(kind),
                            )
                          : controller.more.contains(kind)
                          ? () => controller.load(kind)
                          : null,
                      child: Text(
                        controller.loading.contains(kind)
                            ? ''
                            : controller.failed.contains(kind)
                            ? '加载失败，点击重试'
                            : controller.more.contains(kind)
                            ? '加载更多${kind.label}'
                            : '已显示当前全部内容',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ] else
                  LayoutBuilder(
                    builder: (context, bounds) {
                      final width = (bounds.maxWidth / 3.1 - 8).clamp(
                        104.0,
                        144.0,
                      );
                      final scale =
                          MediaQuery.textScalerOf(context).scale(13) / 13;
                      return SizedBox(
                        height: width * 1.42 + 66 * scale,
                        child: ScrollConfiguration(
                          behavior: const _MioScrollBehavior(),
                          child: ListView.separated(
                            key: PageStorageKey('mio-channel-${kind.name}'),
                            scrollDirection: Axis.horizontal,
                            itemCount: controller.items[kind]!.take(20).length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) => SizedBox(
                              width: width,
                              child: MioPoster(
                                video: controller.items[kind]![index],
                                onTap: () =>
                                    onDetails(controller.items[kind]![index]),
                              ),
                            ),
                          ),
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

class MioPoster extends StatelessWidget {
  const MioPoster({
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
  Widget build(BuildContext context) => Semantics(
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
        identity == null ? 'mio-poster-${video.id}' : 'sdk-poster-$identity',
      ),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, bounds) => SizedBox(
              width: bounds.maxWidth,
              height: bounds.maxWidth * 1.42,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
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
                              colors: [Color(0x80000000), Colors.transparent],
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
                          decoration: const BoxDecoration(
                            color: Color(0xffe7b65c),
                            borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(9),
                            ),
                          ),
                          child: Text(
                            rank == null
                                ? video.score.toStringAsFixed(1)
                                : '$rank',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xff272017),
                              fontSize: rank == null ? 11 : 13,
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
                        statusLabel ?? _status(video),
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

String _metadata(SdkVideo video) {
  final fields = [
    video.year,
    video.area,
  ].where((value) => value.trim().isNotEmpty && value != '0').toList();
  return fields.isEmpty
      ? (video is MioVideo ? video.kind.label : video.categoryName)
      : fields.join(' · ');
}

String _status(SdkVideo video) => video is! MioVideo
    ? ''
    : switch (video.kind) {
        MioKind.movie => '电影',
        MioKind.variety =>
          video.episodeCount > 0 ? '${video.episodeCount}期' : '综艺',
        _ =>
          video.episodeCount > 0 ? '${video.episodeCount}集' : video.kind.label,
      };

/// 分类页与查看更多共用尺寸，文字放大后自动减少列数。
class MioPosterGrid extends StatelessWidget {
  const MioPosterGrid({
    super.key,
    required this.items,
    required this.onDetails,
  });
  final List<MioVideo> items;
  final ValueChanged<MioVideo> onDetails;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      return GridView.builder(
        key: const ValueKey('mio-poster-grid'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: mioPosterGridDelegate(context, bounds.maxWidth),
        itemCount: items.length,
        itemBuilder: (context, index) => MioPoster(
          video: items[index],
          onTap: () => onDetails(items[index]),
        ),
      );
    },
  );
}

SliverGridDelegateWithFixedCrossAxisCount mioPosterGridDelegate(
  BuildContext context,
  double availableWidth,
) {
  final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
  final columns = ((availableWidth + 12) / (112 * scale)).floor().clamp(2, 6);
  final width = (availableWidth - 12 * (columns - 1)) / columns;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: 12,
    mainAxisSpacing: 16,
    mainAxisExtent: width * 1.42 + 66 * scale,
  );
}

class _MioScrollBehavior extends MaterialScrollBehavior {
  const _MioScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

class MioBrowsePage extends StatefulWidget {
  const MioBrowsePage({
    super.key,
    required this.service,
    required this.onDetails,
    this.kind,
    this.categoryId,
  });
  final MioMediaService service;
  final ValueChanged<MioVideo> onDetails;
  final MioKind? kind;
  final String? categoryId;
  @override
  State<MioBrowsePage> createState() => _MioBrowsePageState();
}

class _MioBrowsePageState extends State<MioBrowsePage> {
  final query = TextEditingController();
  final items = <MioVideo>[];
  CancelToken? _cancel;
  int _generation = 0, _page = 0;
  String _keyword = '';
  bool _loading = false, _more = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.categoryId != null) _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loading || !_more)) return;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    final generation = ++_generation;
    if (reset) {
      _keyword = query.text.trim();
      // 新关键词不能沿用上次结果的页号或重试位置。
      setState(() {
        items.clear();
        _page = 0;
        _more = false;
        _error = null;
        _loading = false;
      });
    }
    if (_keyword.isEmpty && widget.categoryId == null) return;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = _keyword.isNotEmpty
          ? await widget.service.search(_keyword, page: page, cancel: cancel)
          : await widget.service.catalog(
              categoryId: widget.categoryId,
              page: page,
              cancel: cancel,
            );
      if (!mounted || cancel.isCancelled || generation != _generation) return;
      final unique = {
        if (!reset)
          for (final v in items) v.identity: v,
      };
      for (final v in result.items) {
        if (widget.kind == null || v.kind == widget.kind) {
          unique[v.identity] = v;
        }
      }
      setState(() {
        items
          ..clear()
          ..addAll(unique.values);
        _page = page;
        // 重复页不是上游结束；继续以来源分页信号判断，保留后续新作品。
        _more = result.hasMore;
      });
    } catch (_) {
      if (mounted && !cancel.isCancelled && generation == _generation) {
        setState(() => _error = '加载失败，请重试');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _cancel?.cancel();
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    child: Scaffold(
      appBar: AppBar(
        // 此页由 MaterialPageRoute 打开，返回同一 Navigator 的页面栈。
        leading: ModernBackButton(
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.kind?.label ?? '影视搜索',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              TextField(
                controller: query,
                onSubmitted: (_) => _load(reset: true),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索作品名称',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: IconButton(
                    tooltip: '搜索',
                    onPressed: () => _load(reset: true),
                    icon: const Icon(Icons.arrow_forward, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Row(
                  children: [
                    Expanded(child: Text(_error!)),
                    TextButton(
                      onPressed: () => _load(reset: _page == 0),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              Expanded(
                child: items.isEmpty && _loading
                    ? SingleChildScrollView(
                        child: LayoutBuilder(
                          builder: (context, bounds) => SkeletonPosters(
                            horizontal: false,
                            count: 6,
                            gridDelegate: mioPosterGridDelegate(
                              context,
                              bounds.maxWidth,
                            ),
                          ),
                        ),
                      )
                    : items.isEmpty
                    ? Center(
                        child: Text(
                          _loading
                              ? '正在加载'
                              : _keyword.isEmpty && widget.categoryId == null
                              ? '输入名称搜索${widget.kind?.label ?? '作品'}'
                              : '暂无符合条件的作品',
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) =>
                            NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (isNearEndScroll(notification) &&
                                    !_loading &&
                                    _more &&
                                    _error == null) {
                                  _load(reset: false);
                                }
                                return false;
                              },
                              child: CustomScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                slivers: [
                                  // 后续页仍按相同尺寸排版，但离屏海报不再整批构建/取图。
                                  SliverGrid.builder(
                                    key: const ValueKey('mio-poster-grid'),
                                    gridDelegate: mioPosterGridDelegate(
                                      context,
                                      constraints.maxWidth,
                                    ),
                                    itemCount: items.length,
                                    itemBuilder: (context, index) => MioPoster(
                                      video: items[index],
                                      onTap: () =>
                                          widget.onDetails(items[index]),
                                    ),
                                  ),
                                  if (_loading)
                                    SliverToBoxAdapter(
                                      child: SkeletonPosters(
                                        horizontal: false,
                                        count: 3,
                                        gridDelegate: mioPosterGridDelegate(
                                          context,
                                          constraints.maxWidth,
                                        ),
                                      ),
                                    ),
                                  if (_more)
                                    SliverToBoxAdapter(
                                      child: TextButton(
                                        onPressed: _loading
                                            ? null
                                            : () => _load(reset: false),
                                        child: const Text('加载更多'),
                                      ),
                                    ),
                                  const SliverToBoxAdapter(
                                    child: SizedBox(height: 24),
                                  ),
                                ],
                              ),
                            ),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
