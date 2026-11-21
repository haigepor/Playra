# 囧次元首页布局分析与 Playra 落地记录

日期：2026-11-16
设备：Lenovo TB711FU（2560×3840 物理像素，480dpi，逻辑 1280×853dp 横屏 / 853×1280dp 竖屏）
目标 App：`com.dskiow.cjsq.p1`（内部包名 `com.yy.myuko.app`，与 CliCli / Myuko 同源）

## 1. 目标首页拆解

### 1.1 实测结构

通过 `uiautomator dump` 读取真实控件边界（数值为物理像素，除以 3 得到 dp）：

| 区域 | 实测边界 / 尺寸 | 结论 |
| --- | --- | --- |
| 左侧栏 | x `0–210px`（70dp），高贯穿全屏 | 固定窄侧栏，4 个项目 |
| 顶部分类 Tab | y `137–275px`（46dp），起始 x `228px`（76dp） | 单行横向 Tab，无第二行筛选 |
| 搜索入口 | 可点击区 x `2073–3564px`（约 497dp 宽、45dp 高） | 搜索为长胶囊，右侧两个图标 |
| 右侧图标 | x `3570–3690`、`3690–3834px`（约 40/48dp） | 日历 + 历史 |
| Hero 主卡 | x `628–3423px`（932dp 宽），y `287–1545px`（419dp 高） | 大 16:9 级主卡 |
| Hero 左/右侧卡 | 左 x `138–598px`（153dp 露出），右 x `3453–3840px`（129dp 露出） | PageView 两侧景深露出 |
| VIP 条 | y 约 `1608–1752px`（48dp 高） | 紫色渐变圆角条，右侧 `免费兑换` |
| 栏目卡片 | 首卡 x `258–1420px`（387dp 宽），下一卡 x `1444–2606px` | 3 列，约 16dp 页面边距、8dp 列间距 |
| 侧栏项目 | x `48–192px`，y `477–644px` 等 | 48×56dp 点击区，图标+11sp 标签 |

竖屏实测（`50_jcy_portrait_try.png`）仍是 70dp 左侧栏 + 3 列卡片，说明侧栏不是仅横屏生效，而是平板宽度断点生效。

### 1.2 视觉语言

| 元素 | 目标实测色值 |
| --- | --- |
| 页面背景 | `#EEEBF3`（浅紫灰） |
| 左侧栏 | `#E1DAF7`（浅紫） |
| 主强调色 | `#9966FF`（紫） |
| VIP 条 | `#EEE3FE` / `#ECDEFF` 渐变 |
| 正文 | `#1A1A1A` |
| 搜索框填充 | `#F2EDF8` |
| 栏目标记 | 红 `#FF6B6B` → 蓝紫 `#6A7BFF` 渐变竖条 |

当前 Playra 全局浅色主色为 `#5267D9`（蓝），因此首页使用独立的 `PlayraHomeTokens` 页面级紫色主题，避免影响搜索/详情/播放页面。

### 1.3 目标首页组成

1. 左侧固定栏：首页 / 新片 / 任务 / 我的（本轮 Playra 保留现有产品语义：发现 / 日历 / 追番 / 我的）。
2. 顶部固定区：分类 Tab（推荐 + 源分类）、搜索胶囊、日历/历史图标。
3. Hero 轮播：大主卡 + 左右露出卡片 + 右下圆点（目标 App 横屏截图显示主卡约 932dp 宽、419dp 高，左右卡只露出 1/6）。
4. VIP 权益条。
5. 内容栏目：每个栏目最多 3 张 3:4 大题图卡片，标题和更新信息在卡片下方，重复向下排列。

## 2. git 历史结论

### 2.1 旧版页面仍在 git 中

| 位置 | 内容 | 结论 |
| --- | --- | --- |
| `HEAD:lib/presentation/modern/` | 旧版现代 UI：112 个文件、约 23,360 行删除量；`modern_home_view.dart` 约 2,036 行 | 旧首页/侧栏的视觉参考 |
| `HEAD:lib/presentation/legacy/legacy_navigation.dart` | `OrientationBuilder` + `NavigationRail`：竖屏底部、横屏侧栏 | 自适应导航结构参考 |
| `399347d2:lib/presentation/modern/modern_shell.dart` | `FSidebar` 宽 88/208dp，断点 `PlayraLayout.compactWidth`（600dp） | 侧栏断点/结构参考 |
| `HEAD:lib/presentation/modern/widgets/modern_feature_carousel.dart` | 645 行卡片景深轮播，中心卡 + 侧卡缩放/透明度 | Hero 轮播参考 |
| `HEAD:docs/verification/android-home-channels-light.png` 等 | 旧版 390×844 首页实拍 | 旧视觉参考 |

### 2.2 为什么没有直接 checkout 旧页面

旧 `modern` 首页依赖：

- `lumina` / `whisklet` / `hongguo` / `bangumi` 旧服务与模型；
- `shadcn_ui 0.57.4`、`skeletonizer`、`pointycastle` 等当前 shell 已移除的依赖；
- 旧 `TabShell` / 旧路由 / 旧主题作用域。

当前工作区是 shell-reset 后的 CliCli-only 工程；完整恢复会引入 24k+ 行旧 UI 和旧数据层，无法与当前 `MediaSource` 模型共存。因此本次采用**视觉基线恢复**：

- 从 git 历史提取旧版导航、轮播、栏目标题、卡片结构；
- 在当前 `lib/pages/discover` 与 `lib/shell` 上重建；
- 不恢复旧 controller、旧路由、旧依赖；
- 保留 `MediaSource`、`MediaFeed`、`MediaSection` 数据契约。

## 3. 当前实现映射

| 目标元素 | Playra 实现 |
| --- | --- |
| 70dp 左侧栏 | `PlayraSideRail`（72dp，`width >= 600` 生效） |
| 顶部 Tab + 搜索 + 图标 | `HomeTopBar`（固定区，分类来自 `loadCategories()`） |
| Hero 大卡轮播 | `HomeBannerCarousel`（`MediaBanner`，PageView 两侧露出） |
| VIP 条 | `HomeVipBanner`（展示型，免费兑换为占位提示） |
| 3 列 3:4 栏目 | `HomeSectionGrid` + `HomePosterCard`（每段取前 3 个 `MediaItem`） |
| 页面紫色背景 | `HomeBackdrop` + `PlayraHomeTokens`（浅/深两套） |
| 旧版场景装饰 | 不恢复缺失 PNG/SVG，用代码渐变 + 半透明圆斑 |
| 栏目“查看更多” | 当 `section.items.length > 3` 时跳 `/browse` |

### 3.1 涉及文件

新增：

- `lib/presentation/theme/playra_home_tokens.dart`
- `lib/shell/playra_side_rail.dart`
- `lib/pages/discover/home_backdrop.dart`
- `lib/pages/discover/home_header.dart`
- `lib/pages/discover/home_sections.dart`
- `lib/pages/discover/home_vip_banner.dart`

修改：

- `lib/shell/shell_page.dart`：按 `LayoutBuilder` 切换左侧栏 / 底部导航；增加状态栏明暗样式。
- `lib/pages/discover/discover_page.dart`：固定顶部栏 + 内容区，Hero/VIP/栏目组装。
- `lib/pages/discover/home_banner.dart`：改为大卡景深轮播。

不改：

- `lib/features/sources/**`（CliCli 数据层）
- `lib/pages/detail/**`、`lib/pages/player/**`
- `pubspec.yaml`（无新依赖）

## 4. 当前验证截图

| 截图 | 内容 |
| --- | --- |
| `docs/assets/home-layout/jcy-home-landscape.jpg` | 目标 App 横屏首页 |
| `docs/assets/home-layout/jcy-home-portrait.jpg` | 目标 App 竖屏首页 |
| `docs/assets/home-layout/playra-home-landscape.jpg` | Playra 横屏新首页 |
| `docs/assets/home-layout/playra-home-portrait.jpg` | Playra 竖屏新首页 |

## 5. 后续验收

1. `flutter analyze` 无错误/警告。
2. 真机横屏 1280×853、竖屏 853×1280 截图检查：
   - 左侧栏显示且可切换；
   - 顶部单行 Tab、搜索、日历/历史位置；
   - Hero 主卡 + 两侧露卡 + 圆点；
   - VIP 条；
   - 3 列 3:4 栏目卡片。
3. 浅色/深色、系统字号 1.0/1.3 无裁切、无 overflow。
4. 搜索、分类、Hero、卡片、详情、播放路由回归。
