import 'package:kazumi/presentation/widgets/playra_page_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/features/sources/core/media_source.dart';
import 'package:kazumi/features/sources/sources.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/pages/discover/media_widgets.dart';
import 'package:kazumi/pages/route_args.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_backdrop.dart';
import 'package:kazumi/presentation/widgets/playra_page_header.dart';
import 'package:kazumi/presentation/widgets/playra_segmented_tab_bar.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, required this.args});

  final BrowseArgs args;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  static const _sorts = <(String, String)>[
    ('', '综合'),
    ('hot', '最热'),
    ('new', '最新'),
    ('score', '评分'),
  ];

  final ScrollController _scroll = ScrollController();
  final List<MediaItem> _items = <MediaItem>[];

  int _revision = 0;
  String _sort = '';
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadMoreFailed = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final initialSort = widget.args.initialSort;
    if (_sorts.any((s) => s.$1 == initialSort)) {
      _sort = initialSort;
    }
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || _loadMoreFailed || !_hasMore) {
      return;
    }
    final position = _scroll.position;
    // 失败后不再随滚动重试：重试入口在页脚，避免一次断网打出几十个请求。
    if (position.pixels > position.maxScrollExtent - 480) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    if (!reset && !_hasMore) return;
    final revision = ++_revision;
    final source = mediaSources.maybeById(widget.args.sourceId);
    if (source == null) {
      setState(() {
        _loading = false;
        _error = const MediaSourceException(
          MediaSourceErrorKind.notFound,
          '内容源不可用',
        );
      });
      return;
    }
    setState(() {
      _loading = true;
      if (reset) {
        _loadMoreFailed = false;
        _error = null;
        _hasMore = true;
        _page = 1;
        _items.clear();
      }
    });
    try {
      final page = await source.browse(
        categoryId: widget.args.categoryId,
        page: _page,
        sort: _sort,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _error = null;
        _loadMoreFailed = false;
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _page += 1;
      });
    } catch (error) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _error = error;
        _loadMoreFailed = _items.isNotEmpty;
      });
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _loading = false);
        // A short page cannot trigger scrolling. Fill it after layout, using
        // the same request revision and failure guards as normal pagination.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              revision != _revision ||
              _loading ||
              !_hasMore ||
              _error != null) {
            return;
          }
          if (_items.isEmpty ||
              (_scroll.hasClients && _scroll.position.maxScrollExtent <= 0)) {
            _load();
          }
        });
      }
    }
  }

  void _selectSort(String value) {
    if (_sort == value) return;
    setState(() => _sort = value);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load(reset: true);
  }

  Future<void> _refresh() async {
    mediaSources.maybeById(widget.args.sourceId)?.invalidateCache();
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayoutMetrics.of(context);
    final homeTokens = PlayraHomeTokens.of(context);
    final selectedIndex = _sorts.indexWhere((s) => s.$1 == _sort);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PlayraBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          layout.gutter,
                          4,
                          layout.gutter,
                          2,
                        ),
                        child: SizedBox(
                          height: 40,
                          child: Row(
                            children: [
                              PlayraCircleAction(
                                tooltip: '返回',
                                icon: Icons.arrow_back_rounded,
                                onTap: () => Navigator.of(context).maybePop(),
                              ),
                              Expanded(
                                child: Text(
                                  widget.args.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: homeTokens.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 36),
                            ],
                          ),
                        ),
                      ),
                      DefaultTabController(
                        length: _sorts.length,
                        initialIndex: selectedIndex < 0 ? 0 : selectedIndex,
                        child: PlayraSegmentedTabBar(
                          labels: [for (final sort in _sorts) sort.$2],
                          horizontalPadding: layout.gutter,
                          verticalPadding: 6,
                          onTap: (index) => _selectSort(_sorts[index].$1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: homeTokens.divider.withValues(alpha: .6),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: layout.contentMaxWidth,
                    ),
                    child: RefreshIndicator(
                      onRefresh: _refresh,
                      color: Theme.of(context).colorScheme.primary,
                      child: _buildBody(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final layout = HomeLayoutMetrics.of(context);
    final insets = EdgeInsets.fromLTRB(
      layout.gutter,
      0,
      layout.gutter,
      PlayraSpace.md,
    );
    if (_items.isEmpty && _error != null) {
      return MediaStateScrollView(
        child: MediaRetryNotice(
          retrying: _loading,
          message: '分类加载失败',
          error: _error,
          onRetry: _load,
        ),
      );
    }
    if (_items.isEmpty && _loading) {
      return const MediaLoadingState(label: '正在加载');
    }
    if (_items.isEmpty) {
      return const MediaStateScrollView(
        child: PlayraPageState(
          icon: Icons.video_library_outlined,
          title: '这个分类还没有内容',
        ),
      );
    }
    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(layout.gutter, 8, layout.gutter, 12),
            child: Text(
              '已加载 ${_items.length} 部作品',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        MediaPosterGrid(
          items: _items,
          showScore: _sort == 'score',
          fixedColumns: 3,
          overlayStatus: true,
          onTap: (item) => context.pushNamed('/detail', arguments: item.key),
          insets: insets,
        ),
        SliverToBoxAdapter(
          child: MediaGridFooter(
            onLoadMore: _hasMore ? () => _load() : null,
            loading: _loading,
            error: _loadMoreFailed ? _error : null,
            onRetry: _loadMoreFailed ? _load : null,
          ),
        ),
      ],
    );
  }
}
