# 新版「我的」页面改造交接

交接时间：2026-10-11。项目：`D:/project/Playra`，自有仓库 `https://github.com/haigepor/Playra.git`。

## 当前交付与 Git 边界

- `main` 是 Playra 定制分支；`kazumi-upstream` 跟踪官方 `upstream/main`。保留共同祖先，禁止为图形分叉重建历史或强推。
- 本轮已收紧追番页头与标签间距，重排追番卡片，统一日历/追番的封面、评分、圆角和操作图标。
- 三页新增独立 SVG 页头装饰：探索轨迹、日历、书签。`ModernPageArt` 不参与点击或读屏，使用主题强调色的低透明度着色。
- 业务控制器、持久化与同步行为没有改动。「我的」页面尚未改造。
- 提交按环境整理、三页视觉优化、交接文档分开。以实时 `git log` 和 `git status` 为准；本次只提交本地 Git，尚未推送。

已记录的功能提交：`07f07cbc`（Git 同步说明与构建脚本）、`2701f65e`（三页视觉优化）。视觉改造回滚点是 `2701f65e`，在确认后续修改后可通过 `git revert 2701f65e` 产生反向提交；不要对整个工作区执行硬重置。交接文档提交哈希从 `git log` 读取，避免文档自引用。

## 「我的」页面现状分析

新版入口为 `/tab/my/`。`lib/pages/my/my_module.dart` 使用 `InterfacePageHost` 在旧版 `MyPage` 与新版 `ModernProfilePage` 之间切换。

新版 `lib/presentation/modern/pages/profile_page.dart` 目前只有「我的空间」标题、一张预览说明卡和六张入口卡：组件实验室、观看历史、离线缓存、播放规则、数据同步、全部设置。

主要问题：

1. 预览说明占据首屏最显眼的位置，观看与管理功能反而排在后面。
2. 六个入口都单独套卡片，层级重复；历史、下载等高频操作与开发入口权重相同。
3. 新版前三页通过 `ModernHomeScope` 使用深色番剧主题和 Lucide 图标，「我的」页仍使用全局主题和 Material 图标。底部 `ModernShell` 只在索引 0–2 强制深色，切到索引 3 时也会切换导航配色。
4. 新版未接入旧版已有的观看统计，功能深度不足。
5. 顶部 `ModernPageScaffold` 有页面样式按钮，内容卡里又有同一入口，需要收敛。

可复用能力：

- `lib/pages/my/my_controller.dart`：MobX `watchStats`；`attach/detach` 订阅历史、下载变化，300ms 合并刷新；同时还负责弹幕屏蔽规则与更新功能，不能为了页面改造破坏这些职责。
- `lib/modules/my/watch_stats.dart`：按番剧 ID 去重、按 `(番剧 ID, 集数)` 去重；仅有进度记录的历史纳入统计；下载数量包含所有状态的集任务。它表示记录过的观看数据，不能改文案为「全部看完」，也不是实际观看时长。
- `lib/pages/my/my_page.dart`：旧版的 `RouteVisibility.isCoveredOf`、控制器挂载与释放范例。进入设置覆盖根页后，应暂停根页统计订阅，回来恢复；页面版本切换不能泄漏订阅。
- `lib/pages/my/my_space_view.dart`：既有功能分组和窄屏/宽屏范例，可参考结构，不复制其高饱和材质与大圆角到新版。
- `lib/services/sync/bangumi_sync_service.dart`：`initialized/username/isConnecting/lastError` 可用于真实连接状态。存在 Token 不等于身份已验证，不能直接展示「已登录」。该服务只公开用户名，没有现成头像数据接口。
- `lib/pages/settings/sync/sync_settings_page.dart`：Bangumi 和 WebDAV 状态呈现参考，设置返回后要刷新。

## 建议的改造方向

- 与前三页统一深色表面、柔和蓝紫强调色、Lucide 线性图标、20px 页面边距和克制的卡片边框；如改变「我的」页及底部主题，需要同时处理 `ModernShell`，只影响新版入口。
- 首屏以「我的」标题、设置动作和真实观看概览为主；空数据时使用有意义的引导，不虚构统计、头像、会员或打卡记录。
- 历史记录、离线缓存作为优先快捷入口；播放规则仍可快速到达。
- 设置分为「观看偏好」「数据与同步」「应用信息」，减少一入口一卡片的重复边框。
- 将页面样式切换放进设置分组，缩小预览说明的视觉权重；保留原有组件实验室入口，放到低优先级的应用/开发分组。
- 可新增手写 `modern-profile-decoration.svg`，延续前三页细线装饰；不要让装饰影响对比度、点击或读屏。
- 账号区为可选项；若加入，应呈现真实的未连接、连接中、失败、已验证状态，不在每次 build 自动触发网络校验。

必须保留的现有路由：

| 功能 | 路由 |
| --- | --- |
| 历史 | `/settings/history/` |
| 下载 | `/settings/download/` |
| 播放规则 | `/settings/plugin/` |
| 同步 | `/settings/sync` |
| 全部设置 | `/settings/` |
| 页面版本 | `/settings/interface` |
| 组件实验室 | `/ui/components` |

可复用旧版路由：`/settings/theme`、`/settings/player`、`/settings/danmaku/`、`/settings/storage`、`/settings/about/`。扩展入口前核验当前模块注册。

## 验证与环境

- 项目本地 Flutter：`.tooling/flutter/bin/flutter.bat`，版本 3.47.6，Dart 3.13.5。不要调用 PATH 里的旧 Flutter/Dart。
- 本轮追番/日历 widget 测试 7/7 通过；现代预览 Web 构建通过。
- 本轮目标范围静态分析无 error/warning，发现页保留 2 条原有字符串插值 info，命令默认退出码 1；不能写成「所有分析检查全绿」。
- 修改前全量 Flutter 测试为 378 通过、7 失败；本轮修复了追番 tooltip finder 的兼容问题并通过对应测试，尚未重新运行全量。首页的旧 fixture/key 漂移需要单独核查，不能宣称已全修复。
- 本轮 Android 调试包构建通过（Gradle 125.9 秒），产物 `build/app/outputs/flutter-apk/app-debug.apk`。日志见 `.tooling/logs/ui-polish-android-build.log`；设备未连接，不能把构建通过等同手机安装或实机交互验收。
- 本地新版浏览器预览：`http://127.0.0.1:8933`；服务生命周期以实际端口检查为准。浏览器 Hive 与 Android 数据分离。

常用命令（PowerShell，在项目根目录执行）：

```powershell
git status --short
git log --oneline -6
& .tooling/flutter/bin/flutter.bat analyze --no-pub
$env:Path="$PWD\.tooling\bin;$PWD\.tooling\python-tools\cmake\data\bin;$PWD\.tooling\python-tools\bin;$env:Path"
& .tooling/flutter/bin/flutter.bat test --no-pub test/modern_library_view_test.dart test/modern_calendar_view_test.dart
& tool/build-android.ps1
& tool/start-home-preview.ps1 -Build -Port 8933
```

首次 Windows native hook 重建如缺 `volatileaccessu.lib`，本地库位于 `.tooling/windows-sdk-libs/volatileaccessu.lib`，已有兼容工具位于 `.tooling/bin`；先查构建分析文档和真实日志，不改系统工具或 pub cache 源码。

## 可直接复制的交接提示词

```text
请继续改造 D:\project\Playra 的安卓新版「我的」页面。先读 docs/handoff-modern-profile.zh.md、docs/project-analysis-20261011.md，并检查实时 git status、git log 与仓库指令。

当前前三页（发现、日历、追番）已经完成一轮深色视觉优化和手写 SVG 页头装饰。下一轮目标是让「我的」页在配色、图标、间距、卡片和信息层级上与它们统一，并补齐真实的观看概览和常用功能入口。

先审查 ModernProfilePage、ModernShell、ModernHomeScope，以及旧版 MyController、WatchStats、MyPage/MySpaceView。旧版已有观看和下载统计，优先复用，不能重复造统计模型、虚构观看时长或把记录集数标成已看完。注意 RouteVisibility、attach/detach、设置返回刷新及页面版本切换的订阅释放。

建议设计：紧凑标题与设置按钮；真实观看概览；历史/下载/规则快捷入口；观看偏好、数据同步、应用信息分组。预览说明和组件实验室降低优先级但保留可达；页面样式切换不要重复出现。可手写一张克制的 SVG 背景装饰，统一 Lucide 图标。新增账号信息时仅展示已验证服务状态，Token 存在不能视为登录成功。

保持现有功能路由、同步行为、持久化格式和旧版界面。仅修改新版呈现与必需接线，先说明设计和改动范围，再实现并验证。若存在真正影响功能范围的歧义，提出一个关键问题，同时继续不依赖答案的检查。

使用项目本地 Flutter，避免依赖或工具链升级。验证 320/390px、大字体、横屏、空数据和有数据状态、点击路由、返回刷新、版本切换；浏览器预览仅用于视觉检查，不能宣称 Android 实机通过。记录既有失败和新增失败，运行必要的 widget 测试、分析和 Android 构建。

main 为我的定制分支，kazumi-upstream 为官方同步分支，保留共同祖先；不要重写历史、强推或把定制提交放到官方分支。新分支按 codex/ 前缀创建。完成后提供中文变更说明、证据、修改文件和回滚方式；提交、推送按本轮用户授权执行。
```

状态：交接分析 DONE；新版「我的」实际改造 NEXT。
