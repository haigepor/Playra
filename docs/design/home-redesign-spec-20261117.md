# Playra 首页响应式重构规格（2026-11-17）

> 2026-11-19 更新：全局 `PlayraTokens` 已切换为同一套淡紫编辑风，搜索、分类、追番、我的、详情等页面也使用 `PlayraBackdrop` / `PlayraPageHeader`，见 [页面设计系统延续](pages/page-system-20261119.md)。

> 设计稿：`docs/design/home/`  
> 实现范围：`lib/pages/discover/**`、`lib/shell/shell_page.dart`、`lib/shell/playra_side_rail.dart`  
> 目标设备：Lenovo TB711FU（2560×3840，480dpi，853×1280dp 竖屏 / 1280×853dp 横屏）

## 1. 设计方向

保留当前浅紫编辑风（lavender editorial）：浅紫背景、卡片式 Hero 轮播（12dp 圆角，左右露出更多相邻卡片）、3:4 海报卡、低饱和遮罩和细边框。栏目展示全部数据并支持左右滑动；背景使用 Codex 生成的淡紫装饰纹理。手机端恢复品牌字标 + 全宽搜索 + 横向分类的清晰层级；平板端保留 72dp 侧栏和单行工具栏；平板横屏增加右侧热播榜，利用横向空间而不把卡片无限拉宽。首页不展示 VIP 会员条，Hero 轮播不显示圆点或页码指示器。

## 2. 断点

| 布局 | 判定 | Shell | 顶部栏 | Hero | 栏目 |
|---|---|---|---|---|---|
| Phone | `shortestSide < 600dp` | 底部导航 48dp | 3 行：品牌 44 + 搜索 48 + 分类 40 | 卡片式 `viewportFraction .78`，高度 170–240dp，无指示器 | 3 列 / 3 个 |
| Tablet Portrait | `shortestSide ≥ 600dp` 且竖屏 | 左侧栏 72dp | 单行：分类 + 搜索 + 图标 | 卡片式 `viewportFraction .66`，高度约 280–420dp，无指示器 | 3 列 / 3 个 |
| Tablet Landscape | `shortestSide ≥ 600dp` 且横屏 | 左侧栏 72dp | 单行：分类 + 搜索 + 图标 | 左侧约 62% Hero + 右侧热播榜 | 4 列 / 4 个 |

手机横屏（如 844×390dp）仍使用 Phone 布局，避免出现平板侧栏。

## 3. 尺寸与间距

| Token | Phone | Tablet Portrait | Tablet Landscape |
|---|---:|---:|---:|
| 页面 gutter | 16 | 24 | 32 |
| 栏目间距 | 28 | 32 | 36 |
| 卡片列间距 | 8 | 16 | 20 |
| 栏目卡片宽度 | 118（短屏 112） | 170 | 180 |
| 栏目交互 | 横向滑动，展示全部数据 | 横向滑动，展示全部数据 | 横向滑动，展示全部数据 |
| 卡片圆角 | 12 | 12 | 12 |
| Hero 卡片圆角 | 12 | 12 | 12 |
| chip 高度（视觉） | 40 | 40 | 40 |
| 图标点击区 | 48 | 48 | 48 |
| 平板最大内容宽 | — | 1000 | 1200 |

卡片 `mainAxisExtent` 由 `3:4 封面 + 标题行 + 副标题行 + 间距` 按 `textScaler` 动态计算，不再使用固定 `+52`。

## 4. 组件映射

| 设计稿区域 | Flutter 实现 | 关键文件 |
|---|---|---|
| 手机品牌行 / 搜索 / 分类 | `HomeTopBar` phone 分支 | `lib/pages/discover/home_header.dart` |
| 平板单行工具栏 | `HomeTopBar` tablet 分支 | 同上 |
| 卡片式 Hero 轮播（无指示器） | `HomeBannerCarousel` | `lib/pages/discover/home_banner.dart` |
| 栏目头 / 横向海报轨 | `HomeSectionGrid` / `HomePosterCard` | `lib/pages/discover/home_sections.dart` |
| 平板横屏热播榜 | `HomeRankingPanel` | `lib/pages/discover/home_ranking_panel.dart` |
| 侧栏品牌标记 | `PlayraSideRail` / `_RailBrandMark` | `lib/shell/playra_side_rail.dart` |
| 布局断点 | `HomeLayoutMetrics` | `lib/pages/discover/home_layout.dart` |

## 5. 产出设计稿

| 文件 | 说明 |
|---|---|
| `docs/design/home/phone-390x844-light.png` | 手机浅色首页 |
| `docs/design/home/phone-390x844-dark.png` | 手机深色首页 |
| `docs/design/home/tablet-portrait-853x1280.png` | 平板竖屏 |
| `docs/design/home/tablet-landscape-1280x853.png` | 平板横屏 |
| `docs/design/home/component-sheet-20261117.png` | 组件规格板 |
| `docs/design/home/hero-carousel-redesign-20261118.png` | Codex 生成的 Hero 卡片轮播设计稿 |
| `docs/design/home/home-decoration-20261118.png` | Codex 生成的首页装饰纹理 |
| `docs/design/home/poster-placeholder.png` | 封面加载失败的品牌占位图（设计素材） |

> 生成图使用原创通用动漫插画，仅作设计与排版参考；实际内容使用 CliCli 返回的封面。

## 6. 验收

实机截图（TB711FU，2026-11-17）：

- `.analysis/screens/home-redesign-20261117/tablet-portrait-final2.png`
- `.analysis/screens/home-redesign-20261117/tablet-landscape-final2.png`
- `.analysis/screens/home-redesign-20261117/phone-360x800-final2.png`
- `.analysis/screens/home-redesign-20261117/phone-360x800-font130.png`
- `.analysis/screens/home-redesign-20261117/phone-360x800-dark.png`

- 360×800、390×844、600×960、853×1280、1024×768、1280×853 无 RenderFlex overflow；
- 1.0 / 1.3 字号、浅色 / 深色下文字不裁切；
- 手机底部导航，平板侧栏，手机横屏不出现侧栏；
- 栏目计数、热播榜标签、更多入口正常；
- `flutter analyze` 0 issue，首页 widget tests 通过；
- ADB 真机截图与设计稿结构一致。
