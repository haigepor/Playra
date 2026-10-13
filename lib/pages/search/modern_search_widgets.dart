part of 'search_page.dart';

extension _ModernSearch on _SearchPageState {
  Widget _modernPage() => Scaffold(
    appBar: SysAppBar(toolbarHeight: 64, title: _searchField()),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(
            960.0,
            math.max(0.0, constraints.maxWidth - 40),
          );
          final inset = (constraints.maxWidth - width) / 2;
          return Observer(
            builder: (_) => CustomScrollView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 8, inset, 24),
                  sliver: SliverMainAxisGroup(
                    slivers: _hasSearched
                        ? _modernResults(width)
                        : [SliverToBoxAdapter(child: _modernDiscovery())],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _modernDiscovery() {
    final c = Theme.of(context).colorScheme;
    final histories = _controller.searchHistories.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _showFilters,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(LucideIcons.slidersHorizontal, size: 20, color: c.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('按条件查找'),
                      const SizedBox(height: 4),
                      Text(
                        '题材 · 季度 · 评分',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: c.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (histories.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Text('最近搜索')),
              if (_managingHistory)
                TextButton(
                  onPressed: () async {
                    await _controller.clearSearchHistory();
                    if (mounted) _setHistoryManagement(false);
                  },
                  child: const Text('清空'),
                ),
              TextButton(
                onPressed: () => _setHistoryManagement(!_managingHistory),
                child: Text(_managingHistory ? '完成' : '管理'),
              ),
            ],
          ),
        ],
        if (histories.isEmpty)
          const SecondaryEmptyState(
            title: '找到下一部想看的番剧',
            description: '输入番名，或按题材和放送时间查找。',
          ),
        for (final history in histories.take(10))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              LucideIcons.history,
              size: 18,
              color: c.onSurfaceVariant,
            ),
            title: Text(
              _readableQuery(history.keyword),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _managingHistory
                ? IconButton(
                    tooltip: '删除这条搜索记录',
                    onPressed: () => _controller.deleteSearchHistory(history),
                    icon: const Icon(LucideIcons.x, size: 18),
                  )
                : Icon(
                    LucideIcons.cornerUpLeft,
                    size: 16,
                    color: c.onSurfaceVariant,
                  ),
            onTap: () => _submit(history.keyword),
          ),
      ],
    );
  }

  List<Widget> _modernResults(double width) {
    final all = _controller.bangumiList.toList();
    final watched = _controller.notShowWatchedBangumis
        ? _controller.loadWatchedBangumiIds()
        : <int>{};
    final abandoned = _controller.notShowAbandonedBangumis
        ? _controller.loadAbandonedBangumiIds()
        : <int>{};
    final items = all
        .where(
          (item) => !watched.contains(item.id) && !abandoned.contains(item.id),
        )
        .toList();
    final busy = _controller.isLoading;
    final filters = SearchParser(_submittedQuery!).toFilterState();
    final c = Theme.of(context).colorScheme;
    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    busy
                        ? '正在搜索…'
                        : all.isEmpty && _controller.lastSearchFailed
                            ? '搜索结果'
                            : '已加载 ${items.length} 部',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!filters.isIdSearch)
                  _SearchSortMenu(
                    value: filters.sort,
                    onChanged: (sort) =>
                        _applyFilters(filters.copyWith(sort: sort)),
                  ),
                IconButton(
                  tooltip: '筛选番剧',
                  onPressed: _showFilters,
                  icon: Icon(
                    LucideIcons.slidersHorizontal,
                    size: 20,
                    color: c.primary,
                  ),
                ),
              ],
            ),
            if (_filterSummary(filters).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final tag in filters.tags)
                      InputChip(
                        backgroundColor: c.surfaceContainerLow,
                        side: BorderSide.none,
                        labelStyle: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: c.onSurfaceVariant),
                        label: Text(tag),
                        onPressed: _showFilters,
                        deleteIcon: const Icon(LucideIcons.x, size: 14),
                        deleteButtonTooltipMessage: '移除“$tag”条件',
                        onDeleted: () => _applyFilters(
                          filters.copyWith(
                            tags: filters.tags.where((x) => x != tag).toList(),
                          ),
                        ),
                      ),
                    if (filters.season.isNotEmpty || filters.dateRange != null)
                      InputChip(
                        backgroundColor: c.surfaceContainerLow,
                        side: BorderSide.none,
                        labelStyle: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: c.onSurfaceVariant),
                        onPressed: _showFilters,
                        deleteIcon: const Icon(LucideIcons.x, size: 14),
                        deleteButtonTooltipMessage: '移除放送时间条件',
                        label: Text(
                          filters.season.isNotEmpty
                              ? filters.season
                              : '${filters.dateRange!.start} 至 ${filters.dateRange!.end}',
                        ),
                        onDeleted: () => _applyFilters(
                          filters.copyWith(season: '', dateRange: null),
                        ),
                      ),
                    if (filters.scoreRange != null ||
                        filters.rankRange != null ||
                        filters.weekdays.isNotEmpty)
                      ActionChip(
                        backgroundColor: c.surfaceContainerLow,
                        side: BorderSide.none,
                        labelStyle: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: c.onSurfaceVariant),
                        label: const Text('更多条件'),
                        onPressed: _showFilters,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      if (busy && all.isEmpty)
        SliverToBoxAdapter(child: _modernSearchSkeleton(width))
      else if (all.isEmpty)
        SliverToBoxAdapter(
          child: SecondaryEmptyState(
            title: _controller.lastSearchFailed ? '暂时无法获取搜索结果' : '没有找到匹配的番剧',
            description: _controller.lastSearchFailed
                ? '请检查网络连接后重试。'
                : '试试其他番名，或放宽筛选条件。',
            action: TextButton(
              onPressed: () => _submit(_submittedQuery!),
              child: const Text('重新搜索'),
            ),
          ),
        )
      else if (items.isEmpty)
        SliverToBoxAdapter(
          child: SecondaryEmptyState(
            title: '结果被观看状态筛选隐藏了',
            action: TextButton(
              onPressed: () async {
                await _controller.setNotShowWatchedBangumis(false);
                await _controller.setNotShowAbandonedBangumis(false);
              },
              child: const Text('显示全部'),
            ),
          ),
        )
      else
        _ModernSearchGrid(items: items, width: width),
      if (busy && all.isNotEmpty)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: _modernSearchSkeleton(width, count: 3),
        )),
      if (all.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: busy
                  ? const SizedBox.shrink()
                  : _controller.lastSearchFailed
                  ? TextButton(
                      onPressed: _loadMore,
                      child: const Text('加载失败，重试'),
                    )
                  : _controller.hasMoreSearchResults
                  ? TextButton(onPressed: _loadMore, child: const Text('加载更多'))
                  : Text(
                      '已加载全部结果',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
        ),
    ];
  }

  Widget _modernSearchSkeleton(double width, {int count = 6}) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final columns = math.max(1, (width / (scale > 1.5 ? 220 : 136)).floor());
    final cardWidth = (width - (columns - 1) * 12) / columns;
    return SkeletonPosters(horizontal: false, count: count,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns, crossAxisSpacing: 12, mainAxisSpacing: 20,
        mainAxisExtent: cardWidth / .7 + 72 * scale,
      ));
  }
}

class _ModernSearchGrid extends StatelessWidget {
  const _ModernSearchGrid({required this.items, required this.width});
  final List<BangumiItem> items;
  final double width;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final columns = math.max(1, (width / (scale > 1.5 ? 220 : 136)).floor());
    final cardWidth = (width - (columns - 1) * 12) / columns;
    final titleStyle = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600);
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: cardWidth);
      final height = painter.height.ceilToDouble();
      painter.dispose();
      return height;
    }

    final titleHeight = measure('番剧\n番剧', titleStyle);
    final metadataHeight = measure(
      '★ 8.2 2026',
      Theme.of(context).textTheme.bodySmall!,
    );
    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 20,
        mainAxisExtent: cardWidth / .7 + titleHeight + metadataHeight + 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.pushNamed('/info/', arguments: item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: .7,
                child: ModernAnimeCover(
                  src: item.images['large'] ?? item.images['common'] ?? '',
                  score: item.ratingScore,
                  votes: item.votes,
                  showRating: false,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: titleHeight,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  if (GStorage.getSetting(SettingsKeys.showRating) &&
                      item.ratingScore > 0)
                    Text(
                      '★ ${item.ratingScore.toStringAsFixed(1)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  Text(
                    item.airDate.length >= 4
                        ? item.airDate.substring(0, 4)
                        : '',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
