import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/features/sources/sources.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/pages/discover/media_widgets.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_backdrop.dart';
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
      if (mounted && revision == _revision) setState(() => _loading = false);
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
    final canSearch = _controller.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PlayraBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(2, 2, layout.gutter, 2),
                    child: Row(
                      children: [
                        BackButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        Expanded(
                          child: MediaSearchField(
                            controller: _controller,
                            autofocus: true,
                            focusNode: _searchFocus,
                            onSubmitted: (_) => _search(),
                            onClear: _clear,
                          ),
                        ),
                        const SizedBox(width: PlayraSpace.sm),
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: canSearch ? _search : null,
                          child: const Text('搜索'),
                        ),
                      ],
                    ),
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
        SliverPadding(
          padding: insets,
          sliver: SliverList.separated(
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: .22),
            ),
            itemCount: _items.length,
            itemBuilder: (context, i) {
              final item = _items[i];
              final coverWidth = (MediaQuery.sizeOf(context).width * .18).clamp(
                56.0,
                88.0,
              );
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

              return InkWell(
                onTap: () => context.pushNamed('/detail', arguments: item.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: coverWidth,
                          height: coverWidth * 4 / 3,
                          child: MediaCoverImage(
                            url: item.cover,
                            fit: BoxFit.cover,
                            cacheWidth:
                                (coverWidth *
                                        MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(children: titleSpans),
                              semanticsLabel: item.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                            ),
                            if (item.metaText.isNotEmpty ||
                                item.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                item.metaText.isNotEmpty
                                    ? item.metaText
                                    : item.subtitle,
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
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: MediaGridFooter(
            loading: _loading,
            error: _loadMoreFailed ? _error : null,
            onRetry: _loadMoreFailed ? () => _search(reset: false) : null,
          ),
        ),
      ],
    );
  }
}
