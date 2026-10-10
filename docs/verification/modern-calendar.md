# 新版放送日历交付记录

日期：2026-10-11。范围：新版日历页面、季度弹层及其数据适配；旧版时间表和发现页面内容保持原有实现。

## 实现范围

- 沿用发现页的深色背景、淡紫色强调、圆角卡片、封面评分和轻量底部遮罩。
- 顶部标题、季度、星期导航与筛选固定；星期可点击或横向滑动切换，短横线随页面滑动。
- 复用收藏与观看历史仓库，支持全部、仅追番、日漫、国漫、隐藏看过/抛弃、放送时间/热度/评分排序。
- 当前季度使用配置中的 Bangumi 排期接口；历史季度使用镜像季度接口或公共搜索分页。网络沿用已有跨平台 BangumiClient。
- 未知星期放入“排期待定”；仅在时间与时区明确时换算为北京时间，不用首播日期猜测每周更新日。
- 下拉刷新、加载/空/失败状态、缓存、快速切季取消、详情并发上限和局部批量更新。
- 季度弹层改为“年份选择 + 四季 2×2 卡片 + 回到当前季度”，支持下拉及左右切换年份，禁止选择未来季度。
- 页面使用顶部安全区域；底部沿用 ModernShell 的安全区域，避免重复留白。

## 文件及影响

| 文件 | 用途与影响 |
| --- | --- |
| `lib/services/calendar/calendar_models.dart` | 独立排期模型、容错转换、地区与时间规范化 |
| `lib/services/calendar/calendar_service.dart` | 排期与详情请求、分页、取消和缓存 |
| `lib/presentation/modern/calendar/modern_calendar_controller.dart` | 星期/季度/筛选状态与仓库事件同步 |
| `lib/presentation/modern/calendar/modern_calendar_view.dart` | 固定导航、列表、筛选及季度弹层入口 |
| `lib/presentation/modern/calendar/widgets/calendar_poster_card.dart` | 日历封面卡片与继续观看入口 |
| `lib/presentation/modern/calendar/widgets/calendar_season_picker.dart` | 紧凑季度选择组件 |
| `lib/presentation/modern/pages/calendar_page.dart` | 替换新版占位页，连接既有仓库、详情和播放路由 |
| `lib/presentation/modern/modern_shell.dart` | 新版日历底栏沿用发现页暗色样式 |
| `test/calendar_service_test.dart` | 接口容错、时间、地区、分页、缓存验证 |
| `test/modern_calendar_controller_test.dart` | 请求竞争、刷新与追番同步验证 |
| `test/modern_calendar_view_test.dart` | 星期点击/滑动、暗色主题、窄屏大字验证 |
| `test/calendar_season_picker_test.dart` | 年份、四季、未来季度与窄屏验证 |

未新增依赖、未调整全局配置，已有规则 HTTP API 不在本次改动范围。

## 验证

- PASS：`flutter analyze --no-pub`，本次日历目录、路由/外壳及四个测试文件无问题。
- PASS：`flutter test --no-pub test/calendar_service_test.dart test/modern_calendar_controller_test.dart test/modern_calendar_view_test.dart test/calendar_season_picker_test.dart test/interface_navigation_test.dart --reporter expanded`，27 项通过。
- PASS：最终 Web 预览构建，入口 `lib/main_home_preview.dart`，输出 `build/modern-home-preview`。
- PASS：`flutter build apk --debug --no-pub`，输出 `build/app/outputs/flutter-apk/app-debug.apk`；本轮未安装到设备或声明原生交互验收通过。
- PASS：真实浏览器 430×880，当前季度与 2026 年春季历史排期、番剧详情请求均 HTTP 200；星期点击、国漫筛选、年份左右切换、年份下拉与返回季度视图可操作。
- PASS：320 宽与 1.5 倍字体 Widget 检查无溢出；新增季度弹层为 2×2 四季布局。
- PASS：UTF-8 严格解码，无 BOM、无替换字符，`git diff --check` 无问题。
- 已修复两个边界：时间换算后重复构建卡片不会重复跨日；详情批处理未提交时刷新，新的详情仍能提交。
- PARTIAL：用户否定当前季度弹层视觉与年份下拉交互，本版仅为功能基线，视觉验收未完成。按用户最新要求转入组件研究，后续方向见 `docs/flutter-calendar-component-options.md` 与 `docs/design/season-picker-component-proposal.svg`。

浏览器截图：`modern-calendar-mobile.png` 为早期页面截图；`modern-calendar-season-picker.png`、`modern-calendar-season-picker-320.png` 记录本轮弹层布局，并不代表用户认可该样式。

Android 构建通过但输出已有 Gradle 8.14.5、AGP 8.11.1、Kotlin 2.2.21 后续支持期限警告；本轮没有调整工具链。

## 数据与平台限制

- 排期为元数据来源的原始放送安排，不能据此保证播放源已更新，也不虚构更新话数或倒计时。
- 多个放送时刻、缺少时区或缺少星期时保留待定；地区未知条目仅在“全部”中展示。
- 历史公共搜索有 500 条上限；达到上限或后续分页失败时展示部分数据提示。
- 新日历与旧版共享收藏、历史与原有筛选设置；旧版控制器本次没有迁移到 CalendarService。
- Android 原生设备布局与继续播放需区分构建证明与真实设备交互证明。

## 回退

本次修改前的已有文件快照位于 `.dart_tool/calendar-work/`：

- `lib__presentation__modern__pages__calendar_page.dart`
- `lib__presentation__modern__modern_shell.dart`

仅恢复上述对应文件，并移除本次新增的 calendar 目录、测试和交付记录即可回退本次实现。若这些文件后续另有修改，应人工对比快照；不可用 Git 全量还原覆盖前序任务或用户修改。
