# 交接提示词：Playra 首页头部重设计落地

> 用法：把下面 `---` 之间的整段作为新会话的第一条消息发送。
> 设计已定稿（`docs/analysis/home-header-redesign-20261103.zh.md`），本提示词只负责执行。

> **2026-11-03 状态更新（分类集合已变，头部规格不变）**：第二个内容源（Whisklet / 追剧喵协议）已接入，
> 分类行改为「推荐 / 热门 + 7 个风格频道（电影 / 电视剧 / 动漫 / 综艺 / 短剧 / AI漫剧 / 电视直播）」，
> `movies / television / variety / shortDrama / aiComic / live` 现在都有真实片源，不再是空页；
> 动漫仍以 Lumina 为主源。本文 §0 / §3「分类行 7 项」「未接入分类不进这一行」与 §6 验收点 2 的字面描述，
> 以 `docs/analysis/home-two-source-integration-20261103.zh.md` 为准；头部结构、尺寸、颜色、文案规则不变。

---

请接续 Playra 项目，完成已经定稿的**首页头部重设计**落地。这是执行任务，不是重新设计：结构、尺寸、颜色、分类集合、文案规则都已确认，直接改代码、改测试、跑验收。

## 0. 任务一句话

把 `lib/presentation/modern/home/modern_home_view.dart` 的头部从「两行分类 + 一行滚动区搜索」改成参考图的「两行头部」：**row1 = 品牌块 + 实心搜索胶囊（放大镜在右）+ 日历图标；row2 = 7 项扁平分类文字行（无指示条、无滑块）**。

## 1. 仓库与基线

| 项 | 值 |
|---|---|
| 工作目录 | `C:\Users\haige\Desktop\Playra`（Flutter；Dart package 名仍是 `kazumi`，品牌呈现 Playra，不要全仓重命名） |
| 分支 | `main`，基线 `763f1ae2` |
| 工作树 | 除 `fastlane/.flutter`、`fastlane/.libmpv-android-video-build` 两个子模块漂移外应干净；**不要动这两个子模块** |
| 目标文件 | `lib/presentation/modern/home/modern_home_view.dart`（2036 行） |
| 设计依据 | `docs/analysis/home-header-redesign-20261103.zh.md` |

先跑一遍确认状态，再动手：

```bash
cd /c/Users/haige/Desktop/Playra
git status --short
git log -2 --oneline
flutter --version
```

## 2. 先读这些（按序读完再改）

1. `docs/analysis/home-header-redesign-20261103.zh.md` —— 结构拆解、规格表、落点、测试影响、验收。
2. `lib/presentation/modern/home/modern_home_view.dart:204-400` —— 现有头部组装与滚动区首项。
3. `...:636-750` `_FeedSelector`（TabBar + 下划线指示条）、`...:752-934` `_AnimeFilters`（动漫子分类滑块）、`...:1263-1314` `_SearchEntry`（描边搜索框）。
4. `lib/presentation/modern/home/home_theme.dart` —— **只读 token**（暗色 zinc 板），不要改这个文件。
5. `test/modern_home_view_test.dart:233-284` 与 `:323-391` —— 要改断言的用例。
6. `test/interface_navigation_test.dart:194,311` —— 只依赖 `home-calendar` 这个 key，改完应当仍然通过。

行号以基线 `763f1ae2` 为准；如果与源码不一致，按符号名定位，不要按行号硬改。

## 3. 已确认的设计决策（不要改）

| 项 | 决定 |
|---|---|
| 头部结构 | 两行：row1 品牌块 + 搜索胶囊 + 图标；row2 扁平分类行 |
| 分类行 | 7 项：`推荐 / 热门 / 动漫 / 新番 / 日漫 / 国漫 / 动漫电影`，一一对应 `HomeFeed.recommended/popular/anime/season/japanese/chinese/animeMovies` |
| 选中态 | **无指示条、无底色**；选中 16px / w700 / `onSurface`，未选中 15px / w500 / `onSurfaceVariant` |
| 未接入分类 | `screen / movies / television / variety / comicDrama` **不进**这一行（没有内容源，进去就是空页） |
| 子分类行 | 删除 `_AnimeFilters` 整类（183 行）及其拖动切换手势 |
| 搜索 | 从滚动区上移进固定头部；实心胶囊、无描边、放大镜在文字右侧 |
| 右槽位 | 图标按钮 = 排期表（保留 `ValueKey('home-calendar')` 与 `onCalendar`），**不做九宫格面板** |
| 副标题 | 只写算得出来的：`收录 N 部`（`anime?.browseItems('all').length`）；已接入但未加载 = `正在同步…`；`anime == null` = 空串。**禁止写"今日更新 N 部"**：Lumina 只有 `updatedTo`（集数），没有日期字段，`catalog.airing` 全仓没有加载器接线 |
| 主题 | 一律 `Theme.of(context).colorScheme`，不硬编码色值，不改 `home_theme.dart` |

## 4. 规格（照抄，别重新调）

颜色 token（`home_theme.dart` 暗色板经 `modernHomeTheme` 映射后的取值）：

| token | 值 | 用途 |
|---|---|---|
| `onSurface` | `#edf0f8` | 品牌名、选中项、右侧图标 |
| `onSurfaceVariant` | `#a5afc5` | 副标题、搜索占位、未选中项 |
| `surfaceContainerHighest` | `#202638` | 搜索胶囊填充 |

尺寸：

| 元素 | 值 |
|---|---|
| 头部内边距 | `fromLTRB(20, 6, 20, 8)` |
| row1 行高 | 44（由 44×44 的图标按钮决定；搜索胶囊 40 居中） |
| 品牌名 | 20 / w800 / `letterSpacing -0.3` / `height 1.1` |
| 副标题 | 11 / w500 / `height 1.2`，与品牌名间距 2，行高随 `textScaler` 缩放 |
| 品牌块最大宽 | 112 |
| 搜索胶囊 | 高 40、`StadiumBorder`、左右内边距 14、无描边 |
| 搜索文字 / 图标 | 13 / w500；图标 18，位于文字右侧，间距 8 |
| 图标按钮 | 视觉 44×44（图标 20，`onSurface` alpha .86），`InkResponse` radius 24 |
| 分类行 | minHeight `max(44, textScaler.scale(16) * 1.4)`；每项左右 padding 6，项间额外 `SizedBox(width: 8)` → 文字间 20 |
| row1 → row2 | `SizedBox(height: 8)` |
| 头部总高 | 6 + 44 + 8 + 44 + 8 = **110**（旧：94 固定 + 62 滚动；内容起点 160 → 114） |

## 5. 改动清单

1. **固定区**（`modern_home_view.dart:283-293`）：把 `Padding` 的子节点 `Column(children: [_FeedSelector, _AnimeFilters])` 换成：

   ```dart
   Padding(
     padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
     child: _HomeHeader(
       controller: controller,
       anime: anime,
       onSearch: onSearch,
       onCalendar: onCalendar,
     ),
   ),
   ```

2. **滚动区首项**（`...:336-374`）：删掉 `SliverList` 里的 `Row(_SearchEntry + 排期表 FilledButton)` 和它后面的 `SizedBox(height: 14)`。删完后内容直接从 `_RecommendationBento` / `ModernFeatureCarousel` 开始，`SliverPadding` 的上边距 4 保持不变。

3. **`_FeedSelector` → `_FeedTabs`**（`...:636-750` 整体替换，见 §6）。

4. **删除 `_AnimeFilters`**（`...:752-934` 整类）。删完确认没有残留引用；`flutter analyze` 若报 `unused_element`，说明还有残留。

5. **`_SearchEntry` 重写**（`...:1263-1314`，见 §6）。

6. **新增 `_HomeHeader` / `_HomeBrand` / `_HeaderIconButton`**（放在 `_FeedTabs` 前面即可）。

不要碰：`_RecommendationBento` 及以下内容区、`ModernPageArt`、`SafeArea`、`RefreshIndicator`、分页逻辑。

## 6. 可直接粘贴的实现

```dart
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.controller,
    required this.anime,
    required this.onSearch,
    required this.onCalendar,
  });
  final ModernHomeController controller;
  final LuminaHomeController? anime;
  final VoidCallback onSearch, onCalendar;

  @override
  Widget build(BuildContext context) {
    final total = anime?.browseItems('all').length ?? 0;
    final subtitle = anime == null
        ? ''
        : total > 0
        ? '收录 $total 部'
        : '正在同步…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: _HomeBrand(subtitle: subtitle),
            ),
            const SizedBox(width: 12),
            Expanded(child: _SearchEntry(onSearch: onSearch)),
            const SizedBox(width: 8),
            _HeaderIconButton(
              key: const ValueKey('home-calendar'),
              icon: LucideIcons.calendarDays,
              tooltip: '排期表',
              onTap: onCalendar,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _FeedTabs(controller: controller),
      ],
    );
  }
}

class _HomeBrand extends StatelessWidget {
  const _HomeBrand({required this.subtitle});
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Playra',
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.1,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        // 副标题行高跟随系统字号，避免大字号下被固定高度裁掉。
        SizedBox(
          height: scaler.scale(11) * 1.35,
          child: Text(
            subtitle,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.2,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      container: true,
      button: true,
      label: tooltip,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: .86),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onSearch});
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '搜索动漫或关键词',
      button: true,
      onTap: onSearch,
      child: ExcludeSemantics(
        child: Material(
          color: colors.surfaceContainerHighest,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('home-search'),
            onTap: onSearch,
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '搜索动漫或关键词',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      LucideIcons.search,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedTabs extends StatefulWidget {
  const _FeedTabs({required this.controller});
  final ModernHomeController controller;

  @override
  State<_FeedTabs> createState() => _FeedTabsState();
}

class _FeedTabsState extends State<_FeedTabs> {
  // 顺序即展示顺序；动漫 = 全部，其后是四个动漫子分类。
  static const feeds = [
    HomeFeed.recommended,
    HomeFeed.popular,
    HomeFeed.anime,
    HomeFeed.season,
    HomeFeed.japanese,
    HomeFeed.chinese,
    HomeFeed.animeMovies,
  ];
  final Map<HomeFeed, GlobalKey> _keys = {
    for (final feed in feeds) feed: GlobalKey(),
  };
  HomeFeed? _lastRevealed;

  @override
  void initState() {
    super.initState();
    _lastRevealed = widget.controller.feed;
    widget.controller.addListener(_revealSelected);
  }

  @override
  void didUpdateWidget(covariant _FeedTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_revealSelected);
      widget.controller.addListener(_revealSelected);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_revealSelected);
    super.dispose();
  }

  // 只在选中项变化时回滚视野；加载状态刷新不打断用户的手动横滑。
  void _revealSelected() {
    final feed = widget.controller.feed;
    if (feed == _lastRevealed) return;
    _lastRevealed = feed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _keys[feed]?.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = widget.controller.feed;
    final height = math.max(
      44.0,
      MediaQuery.textScalerOf(context).scale(16) * 1.4,
    );
    return SingleChildScrollView(
      key: const ValueKey('home-feed-selector'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final feed in feeds) ...[
            Semantics(
              key: ValueKey('home-feed-${feed.name}'),
              selected: feed == selected,
              child: InkWell(
                key: _keys[feed],
                borderRadius: BorderRadius.circular(10),
                onTap: () => widget.controller.selectFeed(feed),
                child: SizedBox(
                  height: height,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Center(
                      child: Text(
                        feed.label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: feed == selected ? 16 : 15,
                          fontWeight: feed == selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: feed == selected
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (feed != feeds.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
```

## 7. 测试改动（不改就一定红）

`test/modern_home_view_test.dart` 里 `recommended and popular entries retain only anime navigation`
（基线 246-283 行）整段断言换成：

```dart
    final selector = find.byKey(const ValueKey('home-feed-selector'));
    for (final label in ['推荐', '热门', '动漫', '新番', '日漫', '国漫', '动漫电影']) {
      expect(
        find.descendant(of: selector, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(find.byType(TabBar), findsNothing);

    TextStyle labelStyle(String feed) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey('home-feed-$feed')),
            matching: find.byType(Text),
          ),
        )
        .style!;

    expect(labelStyle('anime').fontSize, 16);
    expect(labelStyle('anime').fontWeight, FontWeight.w700);
    expect(labelStyle('popular').fontSize, 15);
    expect(labelStyle('popular').fontWeight, FontWeight.w500);

    await tester.drag(selector, const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(controller.feed, HomeFeed.recommended);
    await tester.drag(selector, const Offset(400, 0)); // 回到行首再点，避免点到视口外
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-feed-popular')));
    await tester.pumpAndSettle();
    expect(controller.feed, HomeFeed.popular);
    expect(labelStyle('popular').fontWeight, FontWeight.w700);
    await tester.tap(find.byKey(const ValueKey('home-feed-recommended')));
    await tester.pumpAndSettle();
    expect(controller.feed, HomeFeed.recommended);
    controller.selectFeed(HomeFeed.season);
    await tester.pumpAndSettle();
    expect(labelStyle('season').fontWeight, FontWeight.w700);
    expect(labelStyle('anime').fontWeight, FontWeight.w500);
    expect(
      find.byKey(const PageStorageKey('home-channel-main')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
```

其它用例：

- `feed selection loads new subjects and retry recovers an empty response`（基线 383-387）语义不变，`home-feed-anime` → `find.text('新番')` 仍可用，不需要改。
- `search, calendar, details and resume preserve callbacks and identity`（基线 323-362）：`home-search` / `home-calendar` 两个 key 都保留了，不需要改。
- `test/interface_navigation_test.dart` 不改。

如果还有其它测试引用了被删的 `_AnimeFilters` 或 TabBar 断言，按同样口径改为文字样式断言。

## 8. 验收

```bash
cd /c/Users/haige/Desktop/Playra
flutter analyze
flutter test test/modern_home_view_test.dart test/interface_navigation_test.dart
```

判据：`flutter analyze` 0 error / 0 warning；两个测试文件全绿。
`flutter test` 全量还有 3 个**预存**失败（`browse_auto_load_test` / `content_skeleton_test` / `modern_profile_test`），与本任务无关，**不要去修**，也不要因此改断言。

真机三项（有设备再做，没有就标 `NOT RUN` + 命令）：

1. 320 / 390 / 844×390 三种宽度头部不溢出（`adb shell wm size` / 横竖屏各看一眼）；
2. 7 个分类逐一点击，内容与之前 `推荐/热门/动漫+子分类` 一一对应；
3. 系统字号 1.6 倍：分类行仍单行、可横滑，副标题不被裁。

## 9. 禁止项

- 不改 `home_theme.dart`、`modern_theme.dart`、底部导航、路由、Lumina 协议层、`pubspec.yaml` 依赖。
- 不新增依赖（`LucideIcons.calendarDays` / `.search` 已在 `lucide_icons_flutter` 3.1.24 里）。
- 不重命名 `HomeFeed` 枚举、不改 `selectFeed` 语义、不动 `primaryCategories`。
- 不写"今日更新 N 部"或任何没有数据来源的文案。
- 不整仓格式化、不顺手修无关测试、不动 `fastlane` 两个子模块、不跑 `flutter build web`。
- 不自动 `git commit` / `git push`，除非用户当轮明确要求。

## 10. 交付格式

改完按这个顺序回报：

1. 改动摘要（每个文件改了什么、删了多少行）；
2. `flutter analyze` 原始输出的结论行；
3. `flutter test` 两个文件的通过数；
4. 真机三项的实际结果，没跑的写 `NOT RUN` + 下一条命令；
5. 与本文不一致的地方（如果源码现状要求偏离规格，说明原因和影响）。

同时把 `docs/analysis/home-header-redesign-20261103.zh.md` 末尾的状态行
「分析完成，代码未改（NOT RUN）」更新为实际结果。

---

## 附：易踩的坑

- `_HeaderIconButton` 用 `InkResponse`，需要 `Scaffold` 提供的 `Material` 祖先——首页已有，别额外套 `Material`。
- `Semantics` 上挂 `onTap` 是给读屏用的，不会造成测试里双触发；`tester.tap` 命中的是 `InkWell`/`InkResponse`。
- `Scrollable.ensureVisible` 必须放在 `addPostFrameCallback` 里，否则在 `notifyListeners` 同帧布局未完成时拿不到 `currentContext`。
- 分类行是横向滚动，**不要**塞进 `Expanded` 或固定宽度容器。
- `_SearchEntry` 的 `Material` 用 `StadiumBorder` + `clipBehavior: Clip.antiAlias`，否则水波纹会溢出圆角。
- 删完 `_AnimeFilters` 后 `math`、`LucideIcons`、`HomeFeed` 仍然有其它用处，不要一起删 import。
