import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../widgets/modern_page_art.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_layout.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import '../home/home_theme.dart';
import 'modern_library_controller.dart';
import 'widgets/library_card.dart';

const _categories = <CollectType?>[
  null,
  CollectType.watching,
  CollectType.planToWatch,
  CollectType.watched,
  CollectType.onHold,
  CollectType.abandoned,
];

class ModernLibraryView extends StatefulWidget {
  const ModernLibraryView({
    super.key,
    required this.controller,
    required this.showRating,
    required this.onDetails,
    required this.onResume,
    required this.onChangeType,
    required this.onSync,
    required this.onStyle,
    required this.onDiscover,
  });
  final ModernLibraryController controller;
  final bool showRating;
  final ValueChanged<BangumiItem> onDetails;
  final ValueChanged<History> onResume;
  final Future<bool> Function(BangumiItem, CollectType) onChangeType;
  final VoidCallback onSync, onStyle, onDiscover;

  @override
  State<ModernLibraryView> createState() => _ModernLibraryViewState();
}

class _ModernLibraryViewState extends State<ModernLibraryView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final TextEditingController _search;
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  bool _searchOpen = false;
  int _categoryIndex = 1;

  @override
  void initState() {
    super.initState();
    _categoryIndex = _categories.indexOf(widget.controller.category);
    _tabs = TabController(
      length: _categories.length,
      vsync: this,
      initialIndex: _categoryIndex,
    );
    _search = TextEditingController(text: widget.controller.query);
    widget.controller.addListener(_onChanged);
  }

  void _onChanged() {
    final index = _categories.indexOf(widget.controller.category);
    if (index == _categoryIndex) return;
    _categoryIndex = index;
    _tabs.animateTo(
      index,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    _resetScroll();
  }

  void _resetScroll() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _toggleSearch([bool? open]) {
    setState(() => _searchOpen = open ?? !_searchOpen);
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    } else {
      _searchFocus.unfocus();
      _search.clear();
      widget.controller.setQuery('');
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _tabs.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    child: Builder(
      builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Theme.of(context).colorScheme.surface,
        ),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
                _toggleSearch(true),
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
                _toggleSearch(true),
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (_searchOpen) _toggleSearch(false);
            },
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: SafeArea(
                bottom: false,
                child: ModernPageArt(
                  kind: ModernPageArtKind.library,
                  contentMaxWidth: 1200,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: ListenableBuilder(
                        listenable: widget.controller,
                        builder: (context, _) {
                          final controller = widget.controller;
                          final colors = Theme.of(context).colorScheme;
                          final entries = controller.entries;
                          return Column(
                            children: [
                              Padding(
                                key: const ValueKey('library-header'),
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  12,
                                  0,
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        '追番',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      key: const ValueKey('library-search'),
                                      tooltip: '搜索追番',
                                      onPressed: _toggleSearch,
                                      icon: Icon(
                                        _searchOpen
                                            ? LucideIcons.x
                                            : LucideIcons.search,
                                        size: 21,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '更多操作',
                                      onPressed: () => _showMore(context),
                                      icon: Icon(
                                        LucideIcons.ellipsis,
                                        size: 21,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TabBar(
                                controller: _tabs,
                                isScrollable: true,
                                tabAlignment: TabAlignment.start,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                dividerColor: Colors.transparent,
                                indicatorSize: TabBarIndicatorSize.label,
                                overlayColor: const WidgetStatePropertyAll(
                                  Colors.transparent,
                                ),
                                splashFactory: NoSplash.splashFactory,
                                indicator: UnderlineTabIndicator(
                                  borderRadius: BorderRadius.circular(2),
                                  borderSide: BorderSide(
                                    width: 3,
                                    color: colors.primary,
                                  ),
                                  insets: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                onTap: (index) => controller.selectCategory(
                                  _categories[index],
                                ),
                                tabs: [
                                  for (final category in _categories)
                                    Tab(
                                      key: ValueKey(
                                        'library-category-${category?.value ?? 0}',
                                      ),
                                      height: 44,
                                      child: Text(
                                        category?.label ?? '全部',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight:
                                              controller.category == category
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: controller.category == category
                                              ? colors.onSurface
                                              : colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (_searchOpen)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    12,
                                    20,
                                    0,
                                  ),
                                  child: ShadInput(
                                    controller: _search,
                                    focusNode: _searchFocus,
                                    placeholder: const Text('搜索名称或别名'),
                                    leading: Icon(
                                      LucideIcons.search,
                                      size: 17,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    trailing: _search.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: '清空搜索',
                                            icon: Icon(
                                              LucideIcons.x,
                                              size: 16,
                                              color: colors.onSurfaceVariant,
                                            ),
                                            onPressed: () {
                                              _search.clear();
                                              controller.setQuery('');
                                              _resetScroll();
                                            },
                                          ),
                                    onChanged: (value) {
                                      controller.setQuery(value);
                                      _resetScroll();
                                    },
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  14,
                                  0,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        controller.query.trim().isEmpty
                                            ? '${controller.count(controller.category)} 部番剧'
                                            : '${entries.length} 部匹配',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    ShadButton.ghost(
                                      key: const ValueKey('library-sort'),
                                      height: 44,
                                      size: ShadButtonSize.sm,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      onPressed: () => _showSort(context),
                                      trailing: const Icon(
                                        LucideIcons.chevronDown,
                                        size: 13,
                                      ),
                                      child: Text(
                                        controller.sort.label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (controller.error != null)
                                TextButton(
                                  onPressed: controller.reloadLocal,
                                  child: Text(controller.error!),
                                ),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final scale =
                                        MediaQuery.textScalerOf(
                                          context,
                                        ).scale(14) /
                                        14;
                                    final minimumWidth =
                                        310 * math.max(1, scale);
                                    final columns =
                                        controller.layout == CollectLayout.cards
                                        ? ((constraints.maxWidth - 28) /
                                                  minimumWidth)
                                              .floor()
                                              .clamp(1, 3)
                                        : (constraints.maxWidth >=
                                                  math.max(
                                                    900,
                                                    minimumWidth * 2 + 40,
                                                  )
                                              ? 2
                                              : 1);
                                    return CustomScrollView(
                                      key: const ValueKey('library-results'),
                                      controller: _scroll,
                                      keyboardDismissBehavior:
                                          ScrollViewKeyboardDismissBehavior
                                              .onDrag,
                                      slivers: [
                                        if (entries.isEmpty)
                                          SliverFillRemaining(
                                            hasScrollBody: false,
                                            child: _empty(context, controller),
                                          )
                                        else
                                          SliverPadding(
                                            padding: const EdgeInsets.fromLTRB(
                                              20,
                                              4,
                                              20,
                                              20,
                                            ),
                                            sliver: SliverGrid.builder(
                                              itemCount: entries.length,
                                              gridDelegate:
                                                  SliverGridDelegateWithFixedCrossAxisCount(
                                                    crossAxisCount: columns,
                                                    mainAxisExtent:
                                                        LibraryCard.heightFor(
                                                          context,
                                                        ),
                                                    mainAxisSpacing: 12,
                                                    crossAxisSpacing: 12,
                                                  ),
                                              itemBuilder: (context, index) {
                                                final entry = entries[index];
                                                return LibraryCard(
                                                  key: ValueKey(
                                                    'library-card-${entry.item.id}',
                                                  ),
                                                  entry: entry,
                                                  showRating: widget.showRating,
                                                  pending: controller.isPending(
                                                    entry.item.id,
                                                  ),
                                                  onDetails: () => widget
                                                      .onDetails(entry.item),
                                                  onResume:
                                                      !controller.canSync ||
                                                          entry.history == null
                                                      ? null
                                                      : () => widget.onResume(
                                                          entry.history!,
                                                        ),
                                                  onManage:
                                                      controller.canEdit(
                                                        entry.item.id,
                                                      )
                                                      ? () => _showStatus(
                                                          context,
                                                          entry,
                                                        )
                                                      : null,
                                                );
                                              },
                                            ),
                                          ),
                                      ],
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
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _empty(BuildContext context, ModernLibraryController controller) {
    final searching = controller.query.trim().isNotEmpty;
    final emptyLibrary = controller.count(null) == 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? LucideIcons.search : LucideIcons.bookmark,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              searching
                  ? '没有匹配的番剧'
                  : emptyLibrary
                  ? '还没有追番'
                  : '这里还没有${controller.category?.label ?? '收藏'}的番剧',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? '换个名称或别名试试'
                  : emptyLibrary
                  ? '在番剧详情页加入收藏，随时回来继续观看'
                  : '可以切换分类，或在番剧菜单中修改状态',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            ShadButton.outline(
              onPressed: searching
                  ? () {
                      _search.clear();
                      controller.setQuery('');
                    }
                  : emptyLibrary
                  ? widget.onDiscover
                  : () => controller.selectCategory(null),
              child: Text(
                searching
                    ? '清空搜索'
                    : emptyLibrary
                    ? '去发现番剧'
                    : '查看全部',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sheet(
    BuildContext context,
    String title,
    Widget Function(BuildContext) content,
  ) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => ModernHomeScope(
      child: Builder(
        builder: (context) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .8,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          LucideIcons.x,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  content(context),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _showSort(BuildContext context) => _sheet(
    context,
    '排序方式',
    (context) => Column(
      children: [
        for (final sort in LibrarySort.values)
          ListTile(
            title: Text(sort.label),
            trailing: widget.controller.sort == sort
                ? Icon(
                    LucideIcons.check,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            onTap: () {
              widget.controller.setSort(sort);
              _resetScroll();
              Navigator.of(context).pop();
            },
          ),
      ],
    ),
  );

  Future<void> _showMore(BuildContext context) => _sheet(
    context,
    '追番管理',
    (context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Column(
        children: [
          ListTile(
            leading: Icon(
              LucideIcons.refreshCw,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: const Text('同步收藏'),
            subtitle: const Text('WebDAV / Bangumi'),
            enabled: widget.controller.canSync,
            onTap: () {
              Navigator.of(context).pop();
              widget.onSync();
            },
          ),
          ListTile(
            leading: Icon(
              LucideIcons.layoutGrid,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: const Text('切换布局'),
            subtitle: Text(
              widget.controller.layout == CollectLayout.list
                  ? '当前：列表'
                  : '当前：卡片',
            ),
            onTap: () {
              widget.controller.setLayout(
                widget.controller.layout == CollectLayout.list
                    ? CollectLayout.cards
                    : CollectLayout.list,
              );
              _resetScroll();
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            leading: Icon(
              LucideIcons.palette,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: const Text('切换页面样式'),
            onTap: () {
              Navigator.of(context).pop();
              widget.onStyle();
            },
          ),
        ],
      ),
    ),
  );

  Future<void> _showStatus(BuildContext context, LibraryEntry entry) => _sheet(
    context,
    '修改追番状态',
    (sheetContext) => ListenableBuilder(
      listenable: widget.controller,
      builder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (final type in CollectType.values.where(
            (type) => type.isCollected,
          ))
            ListTile(
              key: ValueKey('library-status-${type.value}'),
              title: Text(type.label),
              enabled: widget.controller.canEdit(entry.item.id),
              trailing: entry.status == type
                  ? Icon(
                      LucideIcons.check,
                      size: 18,
                      color: Theme.of(sheetContext).colorScheme.primary,
                    )
                  : null,
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(widget.onChangeType(entry.item, type));
              },
            ),
          const Divider(),
          ListTile(
            leading: Icon(
              LucideIcons.trash2,
              size: 18,
              color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
            ),
            title: const Text('移除收藏'),
            enabled: widget.controller.canEdit(entry.item.id),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(_confirmRemove(context, entry));
            },
          ),
        ],
      ),
    ),
  );

  Future<void> _confirmRemove(BuildContext context, LibraryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ModernHomeScope(
        child: AlertDialog(
          title: const Text('移除收藏？'),
          content: Text('将“${entry.title}”从收藏中移除，观看记录会保留。'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(true),
              child: const Text('移除'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await widget.onChangeType(entry.item, CollectType.none);
    }
  }
}
