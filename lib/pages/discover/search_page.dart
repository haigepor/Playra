import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/features/sources/sources.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/pages/discover/media_widgets.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_backdrop.dart';
import 'package:kazumi/presentation/widgets/playra_page_header.dart';
import 'package:kazumi/presentation/widgets/media_cover_image.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final List<MediaItem> _items = <MediaItem>[];

  int _total = 0;
  int _revision = 0;
  String _keyword = '';
  int _page = 1;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadMoreFailed = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients ||
        _loading ||
        _loadMoreFailed ||
        !_hasMore ||
        _keyword.isEmpty) {
      return;
    }
    final position = _scroll.position;
    if (position.pixels > position.maxScrollExtent - 480) {
      _search(reset: false);
    }
  }

  Future<void> _search({bool reset = true}) async {
    if (_loading && !reset) return;
    final keyword = reset ? _controller.text.trim() : _keyword;
    if (keyword.isEmpty) {
      _clear();
      return;
    }
    if (!reset && !_hasMore) return;
    final source = mediaSources.primary;
    if (source == null) {
      setState(() => _error = '尚未注册任何内容源');
      return;
    }
    final revision = ++_revision;
    if (reset) {
      FocusScope.of(context).unfocus();
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _keyword = keyword;
      _page = 1;
      _hasMore = true;
      _items.clear();
      _loadMoreFailed = false;
      _error = null;
    }
    setState(() {
      _loading = true;
    });
    try {
      // 翻页只认提交时的关键词：用户改输入框但没提交时，不能把第 2 页搜成
      // 另一个词。
      final result = await source.search(_keyword, page: _page);
      if (!mounted || revision != _revision) return;
      setState(() {
        _error = null;
        _loadMoreFailed = false;
        _items.addAll(result.items);
        _total = result.total;
        _hasMore = result.hasMore;
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
            _search(reset: false);
          }
        });
      }
    }
  }

  void _clear() {
    _revision++;
    _controller.clear();
    _searchFocus.requestFocus();
    setState(() {
      _items.clear();
      _error = null;
      _loading = false;
      _keyword = '';
      _page = 1;
      _hasMore = false;
      _loadMoreFailed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayoutMetrics.of(context);
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canSearch = _controller.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PlayraBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: layout.isPhone
                    ? layout.contentMaxWidth
                    : layout.contentMaxWidth.clamp(0.0, 960.0),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      layout.gutter - 4,
                      8,
                      layout.gutter,
                      10,
                    ),
                    child: Row(
                      children: [
                        if (!layout.isPhone) ...[
                          const SizedBox(width: 4),
                          Text(
                            'Playra',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(width: PlayraSpace.md),
                          SizedBox(
                            height: 22,
                            child: VerticalDivider(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          const SizedBox(width: PlayraSpace.xs),
                        ],
                        PlayraCircleAction(
                          tooltip: '返回',
                          icon: Icons.arrow_back_rounded,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: MediaSearchField(
                            controller: _controller,
                            showIcon: true,
                            autofocus: true,
                            focusNode: _searchFocus,
                            onSubmitted: (_) => _search(),
                            onClear: _clear,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (layout.isPhone)
                          TextButton(
                            onPressed: canSearch ? _search : null,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              foregroundColor: t.accent,
                              disabledForegroundColor: t.textSecondary
                                  .withValues(alpha: 0.45),
                            ),
                            child: const Text(
                              '搜索',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
                          FilledButton(
                            onPressed: canSearch ? _search : null,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(76, 42),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                            child: const Text('搜索'),
                          ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.065)
                        : t.divider.withValues(alpha: 0.7),
                  ),
                  Expanded(child: _buildBody(context)),
                ],
              ),
            ),
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
          message: '搜索失败',
          error: _error,
          onRetry: () {
            _searchFocus.unfocus();
            _search(
              reset: _keyword.isEmpty || _controller.text.trim() != _keyword,
            );
          },
        ),
      );
    }
    if (_items.isEmpty && _loading) {
      return const MediaLoadingState(label: '正在搜索');
    }
    if (_items.isEmpty && _keyword.isEmpty) return const SizedBox.shrink();
    if (_items.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.fromLTRB(layout.gutter, 12, layout.gutter, 0),
          child: Semantics(
            liveRegion: true,
            child: Text(
              '没有找到相关作品',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(layout.gutter, 12, layout.gutter, 8),
            child: Text(
              layout.isPhone
                  ? (_total > 0 ? '找到 $_total 部作品' : '已加载 ${_items.length} 部作品')
                  : (_total > 0
                        ? '搜索结果：$_total 条'
                        : '搜索结果：已加载 ${_items.length} 条'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        SliverPadding(
          padding: insets,
          sliver: SliverList.separated(
            separatorBuilder: (_, _) => layout.isPhone
                ? Divider(
                    height: 1,
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: .22),
                  )
                : const SizedBox(height: 8),
            itemCount: _items.length,
            itemBuilder: (context, i) {
              final item = _items[i];
              final coverWidth = layout.isPhone ? 96.0 : 168.0;
              final matches = RegExp(
                RegExp.escape(_keyword),
                caseSensitive: false,
              ).allMatches(item.title);
              final titleSpans = <TextSpan>[];
              var end = 0;
              for (final match in matches) {
                titleSpans.add(
                  TextSpan(text: item.title.substring(end, match.start)),
                );
                titleSpans.add(
                  TextSpan(
                    text: item.title.substring(match.start, match.end),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                );
                end = match.end;
              }
              titleSpans.add(TextSpan(text: item.title.substring(end)));

              final status = item.subtitle.isNotEmpty
                  ? item.subtitle
                  : item.episodeCount > 0
                  ? '${item.episodeCount} 集'
                  : '';
              return Material(
                color: layout.isPhone
                    ? Colors.transparent
                    : PlayraTokens.of(context).surface,
                borderRadius: BorderRadius.circular(layout.isPhone ? 0 : 12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () =>
                      context.pushNamed('/detail', arguments: item.key),
                  child: Padding(
                    padding: layout.isPhone
                        ? const EdgeInsets.symmetric(vertical: 12)
                        : const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: coverWidth,
                            height: coverWidth * 2 / 3,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                MediaCoverImage(
                                  url: item.cover,
                                  fallbackUrl: item.fallbackCover,
                                  fit: BoxFit.cover,
                                  cacheWidth:
                                      (coverWidth *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .round(),
                                ),
                                if (status.isNotEmpty)
                                  Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: coverWidth - 8,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: .72,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          status,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text.rich(
                                TextSpan(children: titleSpans),
                                semanticsLabel: item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (item.metaText.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  item.metaText,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: MediaGridFooter(
            onLoadMore: _hasMore ? () => _search(reset: false) : null,
            loading: _loading,
            error: _loadMoreFailed ? _error : null,
            onRetry: _loadMoreFailed ? () => _search(reset: false) : null,
          ),
        ),
      ],
    );
  }
}
