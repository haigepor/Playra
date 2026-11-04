# 首页头部重设计（参考图 2 红框区）

结论先行：把现在"两行分类 + 一行搜索按钮"的头部，压成**两行**——第一行 `品牌块 | 搜索胶囊 | 图标`，
第二行 `扁平分类文字行（无指示条）`；搜索从滚动区上移进固定头部，动漫子分类行整体取消。
固定头部高度 94 → 110 px，内容区首屏反而多出约 46 px。

## 1. 参考图拆解（图 2 红框）

| 行 | 单元格 | 内容 | 视觉处理 |
|---|---|---|---|
| 1 | 左 | 品牌 `GUAZI` + 副标 `今日更新99部` | 主名白色粗体，副标 11px 灰，上下贴紧 |
| 1 | 中 | 搜索胶囊，占位是**具体片名**，放大镜在**右** | 实心深灰、无描边、全圆角 |
| 1 | 右 | 九宫格图标 | 纯图标、无容器、与背景同层 |
| 2 | 整行 | 热门/动漫/漫剧/电影/国产剧/短剧 | 纯文字、**无指示条无底色**、左对齐、等距 |

这套头部只有 **4 条视觉规则**：

1. **一个形状**：全头部只有搜索胶囊是"容器"，其余都是文字和裸图标 → 视觉重心唯一。
2. **三级对比**：白（品牌 / 选中项）→ 中灰（副标 / 未选中）→ 深灰（占位符），没有别的强调色。
3. **选中靠字重和颜色**，不靠下划线或滑块；6 个短词在暗底上本来就能一眼分辨。
4. **两行高度差**：行 1 约 40–44，行 2 约 36–40，行间 8–10；副标与品牌名之间几乎无间距，形成"一个块"。

## 2. Playra 现状（`modern_home_view.dart`）

```text
固定区（不滚动）  _FeedSelector        TabBar 推荐/热门/动漫 + 3px 主色下划线   h=44
                  _AnimeFilters        全部/新番/日漫/国漫/动漫电影 滑块分段     h=38
滚动区第一屏      _SearchEntry 48 + 排期表 FilledButton 44                    h=62
```

高度账：固定 94 px，内容首屏先被搜索行吃掉 62 px → 第一张卡从约 160 px 开始。

五条诊断：

| # | 问题 | 依据 |
|---|---|---|
| 1 | 形状语言太多 | 描边输入框 + 实心主色按钮 + 下划线指示条 + 圆角滑块，一屏四种形状 |
| 2 | 层级颠倒 | 搜索是主操作，却在滚动区里先滚走；分类是次操作，反而常驻 |
| 3 | 搜索像表单不像入口 | `outline #30384a` 描边 + 左侧主色图标，读起来是"输入框"；参考图是无描边实心胶囊 |
| 4 | 排期表过重 | 44px 实心主色按钮与搜索抢焦点，而且底部导航已有"日历" |
| 5 | 两行导航 | 主分类 3 个 + 子分类 5 个，占 82 px 固定高度，换来的只是 5 个只在动漫下有效的筛选项 |

## 3. 目标结构

```text
┌────────────────────────────────────────────────────────────┐  背景 #11141c（PageArt 20% 透出）
│  Playra          ╭──────────────────────────────╮           │
│  收录 128 部     │ 搜索动漫或关键词          ⌕  │    ▦      │  row1 h=44（胶囊 40 居中）
│                  ╰──────────────────────────────╯           │
│  推荐   热门   动漫   新番   日漫   国漫   动漫电影          │  row2 h=44（可横滑）
└────────────────────────────────────────────────────────────┘
   20px            搜索占满剩余宽度              40px      20px
```

390 宽下的宽度账：`20 + 76(品牌) + 12 + 206(搜索) + 8 + 40(图标) + 20 = 382`。

## 4. 规格（token 全部取 `home_theme.dart` 的 zinc 暗色板）

| 元素 | 尺寸 | 颜色 / 字体 |
|---|---|---|
| 头部容器 | 内边距 `fromLTRB(20, 6, 20, 8)` | — |
| 品牌名 | 20 px，`w800`，`letterSpacing -0.3` | `foreground #edf0f8` |
| 副标题 | 11 px，`w500`，`height 1.2`，与品牌名间距 2 | `mutedForeground #a5afc5` |
| 搜索胶囊 | 高 40，圆角 20（全圆），左右内边距 14 | 填充 `muted #202638`，**无描边** |
| 搜索提示 | 13 px，`w500`，单行省略 | `mutedForeground #a5afc5` |
| 搜索图标 | 18 px，位于文字**右侧**，间距 8 | `mutedForeground #a5afc5` |
| 右侧图标按钮 | 视觉 40×40、命中 44×44、圆角 12 | 图标 20 px `foreground`，按压缩放填充 `muted` |
| 分类行 | 高 44，项间距 20，左对齐，可横滑 | 选中 16/w700 `foreground`；未选中 15/w500 `mutedForeground` |
| 行间距 | row1 → row2 = 8 | — |
| 头部总高 | 6 + 44 + 8 + 44 + 8 = **110** | 旧：94 固定 + 62 滚动；内容起点 160 → 114 |

形状数量：4 → 1（只剩搜索胶囊）。

## 5. 分类行扁平化

`_FeedSelector`(3) + `_AnimeFilters`(5) 合并成一行 7 项，`controller.selectFeed` 一一对应：

| 新行项 | HomeFeed | 原位置 |
|---|---|---|
| 推荐 | `recommended` | 主分类 1 |
| 热门 | `popular` | 主分类 2 |
| 动漫 | `anime`（即"全部"） | 主分类 3 |
| 新番 | `season` | 子分类 2 |
| 日漫 | `japanese` | 子分类 3 |
| 国漫 | `chinese` | 子分类 4 |
| 动漫电影 | `animeMovies` | 子分类 5 |

- 选中判定从"子分类一律归到动漫"改为 `feeds.indexOf(controller.feed)`，逻辑反而更短。
- `_AnimeFilters` 整类删除（含拖动切换手势）；7 个 tab 点击距离与拖动成本相当。
- 未接入内容源的 `screen / movies / television / variety / comicDrama` **不进**这一行——进去就是空页。

## 6. 副标题文案：只写算得出来的

参考图的"今日更新99部"依赖逐条更新时间戳。当前 Lumina 目录里唯一的更新字段是
`LuminaVideo.updatedTo`（"更新至第 N 集"），**没有日期**，`catalog.airing` 也没有任何加载器接线
（`loadCatalog` / `loadProgressiveCatalog` 全仓无调用点）。所以不写"今日更新 N 部"，改写：

| 状态 | 文案 |
|---|---|
| `anime != null` 且已加载条目 > 0 | `收录 {n} 部`（n = `browseItems('all').length`，已按 id 去重） |
| 已接入但尚未拉到数据 | `正在同步…` |
| `anime == null`（Lumina 未启用） | 空字符串，保留行高 |

等哪天目录带回时间戳，只改这一行文案即可，布局不动。

## 7. 交互与边界

- 分类行横滑只滚动，不切分类（保留现有测试语义）；点击才切。
- 选中项变化后 `Scrollable.ensureVisible` 把它带回视野（7 项在 320 宽下会溢出）。
- 每个 tab `Semantics(selected: …)`；搜索入口保留 `label: '搜索动漫或关键词'`；右侧按钮 `tooltip: '排期表'`、key `home-calendar`。
- `textScaler 1.6`：行高取 `max(44, scaled(16)*1.4)`，文字 `maxLines: 1`。
- 横屏 844×390：头部不折叠（现有 `compact` 只影响 bento），总高 106 在 390 高下仍可用。

## 8. 代码落点

| 位置 | 动作 |
|---|---|
| `modern_home_view.dart:283-293` | 固定区 `Padding` 的子节点换成 `_HomeHeader(controller, anime, onSearch, onCalendar)` |
| `modern_home_view.dart:336-374` | 删掉滚动区首项 `Row(_SearchEntry + 排期表)` 与 `SizedBox(14)`，内容直接从 bento 开始 |
| `modern_home_view.dart:636-750` | `_FeedSelector`（TabBar）→ `_FeedTabs`（无指示条文字行） |
| `modern_home_view.dart:752-934` | 删除 `_AnimeFilters`（183 行） |
| `modern_home_view.dart:1263-1314` | `_SearchEntry` 改为实心胶囊、图标右置、去描边 |
| 新增 | `_HomeBrand`、`_HeaderIconButton`（各 ~30 行） |

骨架（可直接落）：

```dart
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.controller, required this.anime,
      required this.onSearch, required this.onCalendar});
  final ModernHomeController controller;
  final LuminaHomeController? anime;
  final VoidCallback onSearch, onCalendar;

  @override
  Widget build(BuildContext context) {
    final total = anime?.browseItems('all').length ?? 0;
    final subtitle = anime == null
        ? ''
        : total > 0 ? '收录 $total 部' : '正在同步…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _HomeBrand(subtitle: subtitle),
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
```

> `_FeedTabs` 的完整可粘贴实现（key 保持、横向滚动、选中项自动回视野、大字号行高）
> 见 `docs/handoff-home-header-redesign.zh.md` §6；本节只固定落点与约束：
> `home-feed-selector` 留在横向滚动容器上、`home-feed-<name>` 留在每一项上、
> 选中态 = 字号 16 / w700 / `onSurface`，未选中 = 15 / w500 / `onSurfaceVariant`。

## 9. 测试影响（改完必须一起改）

| 文件:行 | 现断言 | 改后 |
|---|---|---|
| `test/modern_home_view_test.dart:246-265` | `TabBar` 3 个 tab、`underline` 宽 3、insets 8、字号 14 | 7 个 `home-feed-*` key；选中项字号 16/w700；未选中 15/w500 |
| 同上 `266-268` | 在 selector 上拖 -250 后 feed 不变 | 保留（横滑只滚动） |
| 同上 `276-278` | `season` 选中后 `tabBar.controller.index == 2` | 改为 `find.text('新番')` 的字重/颜色断言 |
| 同上 `383-387` | 先点 `home-feed-anime` 再点文本"新番" | 语义不变，断言改成 `controller.feed == HomeFeed.season` |
| `test/interface_navigation_test.dart:194,311` | 直接点 `home-calendar` | 不变（图标按钮沿用同一 key） |

## 10. 验收

```bash
flutter analyze                                  # 0 error / 0 warning
flutter test test/modern_home_view_test.dart \
             test/interface_navigation_test.dart  # 全绿
flutter build apk --debug                        # 或走 CI
```

真机三项：① 320/390/844×390 三种宽度无溢出；② 7 个分类逐一点击内容正确切换；
③ 1.6 倍字号下分类行仍单行且可横滑。

状态：**已落地（2026-11-03）**。`flutter analyze` 0 error / 0 warning（482 条 info 均为既有，
本文件与测试无新增）；`flutter test test/modern_home_view_test.dart test/interface_navigation_test.dart`
10 + 9 全绿。真机三项 **NOT RUN**（无设备，命令见 §10）。落地差异：交接文档 §7 的首屏断言按
`ModernHomeController.feed` 默认 `recommended` 校正为「推荐 16/w700、动漫 15/w500」，
其余断言与规格照原文执行。
执行入口见 `docs/handoff-home-header-redesign.zh.md`
（可整段粘贴到新会话：含逐条落点、可直接使用的实现代码、测试断言替换、验收命令与禁止项）。
