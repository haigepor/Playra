# Playra Git、构建环境与安卓新版页面分析

日期：2026-10-11。工作区：`D:/project/Playra`。分析基线：`072d7e67d052c662f98e4b6c56803a7999e8a53b`。

本次为多阶段环境整理，不创建新的 OpenSpec 功能变更；现有 `unify-source-services-http-api` 规范仅作为已提交实现的证据。用户确认保留官方共同祖先，页面继续修改等待后续指令。本次允许修改 Git 本地配置、Git/项目分析文档和 Android 构建脚本，安装产物放在忽略目录；应用业务代码、页面视觉、锁定依赖版本和远程历史均不属于修改范围。

## 1. Git 结论与证据

| 对象 | 本次实时核验 | 含义 |
| --- | --- | --- |
| `origin` | `https://github.com/haigepor/Playra.git` | 用户自己的仓库 |
| `upstream` | `https://github.com/Predidit/Kazumi.git` | Kazumi 官方，只抓取 main |
| `origin/main` / 本地 main | `072d7e67` | 用户开发主线 |
| `origin/kazumi-upstream` | `2768c230` | 用户仓库保存的官方镜像分支 |
| `upstream/main` / 本地 kazumi-upstream | `2768c230` | 与官方当前 main 一致 |
| 完整克隆 | `git rev-parse --is-shallow-repository` 返回 false | 当前没有浅克隆限制 |
| main 可达提交 | 1932 | 官方 1930 条加用户 2 条 |
| 分支独有提交 | `kazumi-upstream...main` 为 `0 2` | 官方没有用户修改；main 包含官方基线 |

```text
Kazumi 官方历史 ── 2768c230                 官方同步分支
                      └── adce00db ── 072d7e67  你的 main
```

两个分支指针处于祖先与后代关系，图形自然可以显示成同一条线。官方提交之后没有新增官方独有提交，所以还不会出现分叉；以后只同步官方分支而尚未集成到 main 时，就会自然出现两条线。

custom 范围内两条提交均只有一个父提交；官方历史内部存在它自己的早期合并记录，这是上游原有历史，不应为了图形整洁删除。不要通过伪造提交、`ours` 合并或创建无共同祖先的根提交制造分叉。

本次完成的本地整理：

- 添加缺失的官方 `upstream`；限制其 fetch refspec 到官方 main。
- 创建本地 `kazumi-upstream`，跟踪 `upstream/main`，设置合并选项 `--ff-only`。
- main 继续跟踪 `origin/main`；两条分支显式设置 `pushRemote=origin`，仓库 `remote.pushDefault=origin`。
- 变更前备份 `.git/config` 和所有 refs 的 Git bundle；没有改写 main、删除分支或推送远程。

详细同步命令见 [git-workflow.md](git-workflow.md)。只看你自己的提交：

```powershell
git log --oneline kazumi-upstream..main
git diff --stat kazumi-upstream main
# 未来只看官方尚未纳入 main 的修改：
git log --oneline main..kazumi-upstream
git diff main...kazumi-upstream
```

`git diff kazumi-upstream main` 展示完整定制差异；`git diff main...kazumi-upstream` 展示共同祖先之后官方一侧的新增差异，两个命令用途不同。

## 2. 两次定制提交究竟包含什么

| 提交 | 标题 | 实际范围 |
| --- | --- | --- |
| `adce00db` | establish Playra customizations on the Kazumi baseline | 272 文件，+25284 / -3924；将已有定制归并到官方基线上 |
| `072d7e67` | 更新发现、日历、追番页面样式 | 96 文件，+11274 / -586；页面实现、数据服务、播放源 HTTP API、测试及文档 |

第一条不是单纯换颜色：新增整个现代呈现层、shadcn 组件画廊、页面版本切换；将网络、平台、播放器等模块拆为 native/web 条件实现；引入本地 `ech_http` 副本与 Windows CA 编译补丁。该提交的 `third_party/ech_http` 占 52 文件、10444 行新增，不能把所有新增行数都解释成自写 UI。

第二条也不只是样式：现代呈现层涉及 17 文件、+5378 / -475；服务层涉及 16 文件、+2462 / -78；新增或更新 11 个测试文件。它同时提交来源模型、规则目录、共享来源服务、HTTP server/client/gateway 和纯 Dart 运行入口。

当前公开 main 历史已经将较早的多个定制步骤压成 `adce00db`；此新克隆的 reflog 只有 clone 记录，不包含旧机器的重建前历史。`MERGE_REPORT.md` 提到的旧机器、旧合并提交、`m3e-player`、浅克隆限制及未推送状态属于过去快照，不能作为当前分支状态依据。该报告提供背景，但不代表当前构建验收。

后续维护建议按功能拆小提交：发现布局、日历交互、追番业务、共享来源服务、构建工具分别提交。已经发布的两条历史保留；根据文件路径追踪现状，不再为了分类重写这些提交。

## 3. 项目架构与运行入口

项目是 Kazumi 的 Flutter 定制应用，不是 Node 前端项目。`pubspec.yaml` 的 Dart 包名仍为 `kazumi`，应用版本 `2.3.8+20308`，要求 Flutter `3.47.6`、Dart `>=3.10.0 <4.0.0`。主要机制为 Flutter Modular 路由/依赖注入、MobX、Hive CE 存储、Dio 网络和 media-kit 播放。

| 位置 | 职责 |
| --- | --- |
| `lib/main.dart` / `lib/app_widget.dart` | 平台初始化、根依赖与应用入口 |
| `lib/pages/index_module.dart` | `/tab` 子模块、详情、播放、设置与组件实验室路由 |
| `lib/presentation/interface_style.dart` | 新旧页面状态与持久化，生产入口仅 Android 支持 modern |
| `lib/presentation/interface_page_host.dart` | 路由内切换页面版本并释放旧页面局部状态 |
| `lib/presentation/shared/tab_shell.dart` | 根导航、RouterOutlet、路由遮挡与 Android 返回键状态 |
| `lib/presentation/legacy` / `lib/pages` | 旧导航与保留的业务页面 |
| `lib/presentation/modern` | 新导航、主题、页面适配、现代视图与控制器 |
| `lib/services` / `lib/request` | 数据、平台、规则、来源、播放器及网络服务 |
| `lib/repositories` / `lib/modules` | 共享收藏/历史等业务状态 |
| `tool/source_api.dart` | 本地来源 HTTP API 入口 |
| `tool/web_backend` | Web 静态服务、跨域代理与 Chromium 解析/验证码；需 Node 依赖 |
| `lib/main_home_preview.dart` | 现代首页的独立 Web 预览入口，不等同生产 Android 实机 |

`InterfacePageHost` 不同时挂载两套页面。切换样式会重建叶子视图，根业务仓库保持存活；`TabShell` 在呈现版本外保留选中项与 outlet。新页面应继续采用“路由适配 → 控制器 → 视图”的边界，收藏、历史和下载不再建一套独立数据库。

Android 的入口是“界面设置 → 页面版本 → 新版界面（预览）”；保存值不是 `modern` 时使用旧版。生产 Web 不开放这项开关，独立预览入口用于开发检查。

## 4. 安卓新页面修改地图

| 页面 | 路由与适配 | 核心修改入口 | 已有行为 |
| --- | --- | --- | --- |
| 发现 | `/tab/popular/`、`modern/pages/discover_page.dart` | `modern/home/modern_home_view.dart`、`modern_home_controller.dart` | 内容分类、首页目录、分页推荐、历史与续播、主题切换 |
| 日历 | `/tab/timeline/`、`modern/pages/calendar_page.dart` | `modern/calendar/modern_calendar_view.dart`、`modern_calendar_controller.dart` | 星期选择、季度入口、筛选、取消过期请求、关联收藏/历史、详情补充 |
| 追番 | `/tab/collect/`、`modern/pages/library_page.dart` | `modern/library/modern_library_view.dart`、`modern_library_controller.dart` | 收藏分类、搜索、排序、列表/网格、状态变更锁定、续播与同步 |
| 我的 | `/tab/my/`、`modern/pages/profile_page.dart` | `modern/widgets/modern_page_scaffold.dart` | 设置/历史/下载/规则/同步入口，仍是较轻的现代页面 |
| 底栏 | `modern/modern_shell.dart` | `shared/tab_shell.dart`、`navigation.dart` | 四个标签、新旧样式共用导航状态 |

### 发现页

发现视图目前约 1677 行，包含多类卡片与布局，是后续视觉修改的主要落点。取数与业务不应塞进该文件。`home_content_algorithm.dart` 根据结构化类型、地区、日期等分类，`home_catalog.dart` / `home_rule_catalog.dart` 连接目录与来源服务，`modern_home_controller.dart` 管理刷新、分页和并发详情补充。

后续需要区分两类修改：间距、封面、标题、栅格属于视图/主题；分类、推荐、分页、来源优先级属于 algorithm/catalog/controller/service。网络无数据与合法空内容需要分开验证。本次全量测试实际发现 6 项首页失败及 1 项追番测试失败；见第 5 节。不能因为旧文档说构建成功就视为测试全绿。

### 日历页

新版日历已从早期占位页发展成实际视图。`docs/modern-calendar-design.md` 中“尚未实施”等句子是设计当时快照，当前代码和测试优先。`CalendarService` 对当前季度、镜像季度、历史分页分别取数；季度缓存 30 分钟（最多 8 份），详情缓存 24 小时（最多 500 条）；历史分页上限、部分数据状态均需保留。

季度筛选控件在 `modern/calendar/widgets/calendar_season_picker.dart`；番剧卡片在 `calendar_poster_card.dart`。控制器通过请求版本与 CancelToken 阻止过期结果覆盖新选择，并在离页时取消请求及定时器。未知放送星期、首播日期、真实播出时间属于不同证据，不能为了展示齐全而相互推导。

### 追番页

`ModernLibraryController` 读取共享收藏与历史；同一 subject 的续播保留最新完整历史记录，不拼接来源、线路和进度。筛选和排序复用 `CollectLibraryQuery`；状态变更以条目 pending/全局 locked 阻止冲突操作。同步和批量动作仍由既有 `CollectController` 承担。

页面改动要覆盖：空收藏、搜索无结果、状态变更失败、同步过程中禁用、列表/网格切换、历史变更自动更新。不要通过重新建立收藏仓库来实现新布局。

### 与官方未来更新的冲突热点

`lib/main.dart`、`lib/app_widget.dart`、页面 module、导航、`lib/plugins`、平台与网络条件导入是官方也可能修改的连接点。现代目录大多是自有新增；`third_party/ech_http` 是本地补丁依赖。集成官方时逐文件比较这些热点，先验证临时分支再进入 main。

## 5. 环境安装与验证记录

初始环境：现有 Flutter `3.38.6` / Dart `3.10.7` 不满足项目 Flutter 版本；PATH 中独立 Dart `3.9.0` 也不满足项目最低 Dart 要求。原 Android 脚本引用旧机器 `C:/Android/Sdk` 与特定 JDK21 路径，本机不存在。不能靠降低 `pubspec.yaml` 的版本约束掩盖差异。

本次使用官方 Flutter tag `3.47.6` 建立项目内 `.tooling/flutter`；Android 工具从 Google SDK repository 元数据获取并核对 SHA1；JDK17 从 Adoptium release API 获取并核对 SHA256。Node 后端使用锁文件执行 `npm ci --ignore-scripts --no-audit`，没有升级依赖。SDK 安装原则见 [Flutter 官方 SDK archive](https://docs.flutter.dev/install/archive)、[Android 工具链说明](https://docs.flutter.dev/platform-integration/android/setup) 和 [sdkmanager 文档](https://developer.android.com/tools/sdkmanager)。

`tool/build-android.ps1` 已支持 `-AndroidSdk` / `-JavaHome` 或环境变量，也能读取本项目 android/local.properties 的 SDK 路径；JDK 可从 `.tooling/java` 自动发现；退出时恢复调用进程环境，避免污染其他项目。它保留原 debug、release、指定设备运行入口。Release 当前仍使用项目已有 debug 签名，不能作为正式发行签名。

### 已安装工具与依赖

- Flutter `3.47.6` / Dart `3.13.5`：`D:/project/Playra/.tooling/flutter`，官方 tag 的 framework SHA 为 `5fc346839b5d0eef006ed8404392afb4dfae428d`。项目 pubspec 最低 Dart 为 3.10，但锁文件已要求 3.13，必须连同锁文件检查。
- Temurin JDK `17.0.20.1+1`：`.tooling/java/jdk-17.0.20.1+1`。
- CMake `4.4.4` 与 Ninja `1.13.2`：`.tooling/python-tools`，只用于本项目原生检查。
- Dart 依赖通过 `flutter pub get --enforce-lockfile` 安装；Node 依赖通过 `npm ci --prefix tool/web_backend --ignore-scripts --no-audit` 安装。两个锁文件均未改动。
- Android SDK：`D:/Android/Sdk`，已安装 platform-tools、platforms/android-31/33/34/35/36、build-tools/35.0.0 与 36.0.0、ndk/28.2.13676358、cmake/3.22.1；旧平台和 Build Tools 35 由本次构建根据插件需求自动补齐；许可证已接受，Flutter doctor 的 Android toolchain 为通过。
- Gradle `8.14.5`：保持项目 wrapper 版本；官方 all 包 SHA256 为 `62c3769155d7d17ea05084ad498067824c1804568a408a6faa78a5ef95ed67a8`，已核对后安装到正常 wrapper cache。

### 实际检查结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Git 引用、对象连接、备份 bundle | PASS | main 保持 `072d7e67`；官方独有 0 / 自有独有 2；bundle verify 与 fsck 成功 |
| Android debug APK 构建 | PASS | `build/app/outputs/flutter-apk/app-debug.apk`，约 142.9 MiB；最终复跑 Gradle 6.6 秒 |
| APK 签名 / ZIP CRC / 原生架构 | PASS | v2 签名有效；ARMv7/ARM64/x64 ECH 与 Flutter 库完整；`.tooling/logs/apk-signature-verify.log` |
| 跨盘 Kotlin 编译回归 | PASS | 强制执行 dynamic_color 编译，10 个任务执行成功；`.tooling/logs/kotlin-cross-drive-regression.log` |
| 构建脚本环境恢复 | PASS | SDK/JDK/Path/NO_PROXY/GRADLE_OPTS 的调用前后值一致，包括未设置变量 |
| Flutter Web 构建 | PASS | `build/web/index.html`；`.tooling/logs/flutter-web-build.log` |
| Flutter 静态分析 | 0 error / 0 warning / 32 info | 默认命令因 info 返回 1；`.tooling/logs/flutter-analyze.log` |
| 全量 Flutter 测试 | FAIL：378 通过，7 失败 | `.tooling/logs/flutter-test.log`，实际执行完毕，不是原生构建阶段退出 |
| 来源 HTTP API 集成 | PASS：32/32 | 真实 Dart RuleEngine + localhost gateway fixture；`.tooling/logs/source-api-integration.log` |
| Node Web 后端测试 | PASS：6/6 | 包括真实 Chromium 解析/验证/取消、代理安全及静态路径边界 |
| Windows 原生 CA 回归 | PASS：1/1 | MSVC 编译及 `build/native-ca-bundle` 的 CTest |

Flutter doctor 的其他提示仍保留：SDK 为固定 tag 的 detached checkout，显示 user-branch；系统 PATH 的 Flutter/Dart 与项目内 SDK 不同；Windows 桌面 workload 未完整安装；系统另有一个 adb。构建脚本临时把本项目 Flutter/JDK/ADB 放在 PATH 首位，并不修改系统默认工具链。

生产 Web 入口使用旧界面；Web 构建通过不等于 Android 新界面实机验收。当前未连接 Android 设备，后续 APK 的设备运行单独记录。

### 七项测试失败的范围与原因

1. `modern_home_controller_test.dart` 的分类保留用例：`Bad state: No element`，第 45 行期待 feed 条目。当前注入 `loadCatalog` 后走结构化 catalog 算法，不再退回该 fixture 的 `loadFeed`。
2. 同文件的并发放送详情用例：期望 3 次请求，实际 0 次。fixture 只含旧 airing map；当前非结构化 catalog 不更新 airing。
3. `modern_home_view_test.dart` 的栏目横向滚动用例：找不到 `home-rating-0`。
4. 同文件的分类拖动用例：找不到旧 `home-feed-season`。
5. 同文件的详情/续播回调用例：找不到 `home-featured-details`。
6. 同文件的空响应恢复用例：旧错误文案与当前“分类数据缺失 / 合法空分类”语义不一致。
7. `modern_library_view_test.dart` 的固定顶部/续播用例：第 97 行把 tooltip finder 返回的 `RawTooltip` 强制视为 `IconButton`，发生类型错误；Flutter 3.47 的 tooltip 包装层需纳入测试查找策略。

上述是日志与当前代码支持的直接原因；不能据此断言所有真实页面行为正确。首页测试 fixture/旧控件假设与结构化数据入口存在漂移，后续需同时确认设计期望与真实交互，再决定修测试还是修实现。本轮未修改业务代码或测试，等待用户页面修改指令。

### 本机原生工具兼容处理

Windows 系统编码与 `vswhere -utf8` 输出不一致，导致 native_toolchain_c 读取中文 JSON 时失败。项目忽略目录 `.tooling/bin/vswhere.exe` 转发原工具输出，将 JSON 的非 ASCII 字符转为 Unicode escape；已验证解析后的数据与原工具一致。未替换系统文件或修改 pub cache。

ECH 预编译库还引用 `volatileaccessu.lib`，本机 Windows SDK 10.0.22621 缺少该库。已从 Microsoft 官方 [Windows SDK x64 NuGet 包](https://www.nuget.org/packages/Microsoft.Windows.SDK.CPP.x64/10.0.26100.9169) 提取真实库到 `.tooling/windows-sdk-libs`，再复制到本次 ECH native build 工作目录供链接器读取，没有删除安全函数或生成 stub。当前缓存路径为 `.dart_tool/hooks_runner/shared/ech_http/build/8e04c28b44/native`；清空缓存后路径可能变化，需要重新放置该库。

在项目根目录复跑检查：

```powershell
$env:Path = "$PWD\.tooling\bin;$PWD\.tooling\python-tools\cmake\data\bin;$PWD\.tooling\python-tools\bin;$env:Path"
& .tooling/flutter/bin/flutter.bat test --no-pub
& .tooling/flutter/bin/cache/dart-sdk/bin/dart.exe run tool/source_api_integration.dart
& .tooling/flutter/bin/flutter.bat build web --no-pub --no-wasm-dry-run
& tool/build-android.ps1 -AndroidSdk 'D:\Android\Sdk'
```

Windows Developer Mode 未开启，首次 pub get 因插件 symlink 生成失败；缓存依赖再次执行已成功。这个 OS 能力限制仍存在，改变插件依赖或 Windows 桌面构建时可能再次触发；Android/Web 构建与 Windows 桌面构建需分别验证。本轮未更改系统 Developer Mode。

### Android 产物与构建兼容处理

- APK：`D:/project/Playra/build/app/outputs/flutter-apk/app-debug.apk`。
- SHA256：`88BBA21A5B292578163C53A676249919C32BC1219506F148C3F716C234B9036A`。
- 实际包信息：`com.predidit.kazumi`，versionCode `20308`，versionName `2.3.8`，target/compile SDK `36`，应用显示名仍为 `Kazumi`。
- 首次安装构建工具、旧插件平台和三种架构 Flutter 调试引擎后，APK 成功生成。最终使用更新后的 `tool/build-android.ps1` 无参数复跑成功，Gradle 阶段为 6.6 秒；`.tooling/logs/flutter-android-build.log` 无 Kotlin daemon / incremental cache 错误。
- APK 检查验证了 v2 签名、完整 ZIP CRC，以及 ARMv7/ARM64/x64 的真实 ELF 架构和 ECH/Flutter 原生库。构建产物可用于后续设备测试；ADB 当前无 Android 设备，未执行手机安装或实机播放验收。

项目在 D 盘而默认 Pub cache 在 C 盘，首次 Kotlin 编译出现 `this and base files have different roots`，回退编译后仍成功产出 APK。脚本已在跨盘时临时通过 `GRADLE_OPTS=-Dorg.gradle.project.kotlin.incremental=false` 关闭 Kotlin 增量编译；其他机器同盘时不改变默认策略。强制重编译 `dynamic_color` 已成功，并确认 Gradle 收到 false；随后整包构建及环境恢复检查也通过。

不能经 Flutter 传递带小写后缀的 `ORG_GRADLE_PROJECT_kotlin.incremental`：Dart 在 Windows 会大写环境变量名，Gradle 项目属性名却区分大小写，因此使用 JVM 属性值保留大小写。脚本退出时对原先不存在的变量使用 `NullString`，避免新版 PowerShell/.NET 把普通 null 绑定成空字符串后遗留变量。依据见 [Dart environment API](https://api.dart.dev/dart-io/Platform/environment.html)、[Gradle 构建属性](https://docs.gradle.org/current/userguide/build_environment.html) 与 [Kotlin 增量编译文档](https://kotlinlang.org/docs/gradle-compilation-and-caches.html)。没有修改系统环境、pub cache 源码、Android Gradle/Kotlin/依赖版本或应用页面。

Flutter 给出 Gradle 8.14.5、AGP 8.11.1、Kotlin 2.2.21 的未来弃用提醒，当前构建通过；Gradle 也提示现有插件含 Gradle 9 不兼容的弃用用法。后续工具链升级需成组检查插件兼容性，不能只升级 wrapper 或绕过验证来处理。

本轮交付：Git 职责整理 DONE；依赖安装及 Android/Web 构建 DONE；提交与页面分析 DONE；验证结果记录 DONE。新版页面修改为 NEXT，等待用户指令。全量测试自身结果仍为 FAIL（378 通过 / 7 失败），不将构建成功等同于测试全绿。

## 6. 保留风险与回滚

- Android applicationId 仍为 `com.predidit.kazumi`，与官方一致；安装同包名版本时可能产生覆盖/签名冲突。本次不改变应用身份，后续品牌迁移需单独决策。
- API keys 通过构建 define 注入；未提供真实私有 key 的本地构建不代表线上全部接口功能已验收。
- `fastlane/.flutter` 与 `.libmpv-android-video-build` 子模块尚未初始化；普通应用构建与 fastlane 原生发布流水线区别对待，按实际构建需求初始化。
- 既有旧报告、设计文档和真实当前实现存在时间差；本报告以本次 Git 和运行命令为准。
- Git 配置回滚文件：`.git/codex-backups/git-organization-20261011/config.before`；完整 refs 快照：同目录 `before.bundle`。当前 main 提交哈希保持原样。
- 文档与构建脚本回滚基线为 `072d7e67`；只按文件恢复本次修改，先检查后续新增改动，不对整个工作区 reset。

后续页面修改等待用户指令；优先明确页面、目标截图/交互与验收范围，再在自有 main 的功能分支实施。


## 7. 后续状态补充（2026-10-11）

本报告前六节记录 Git 整理和初始构建的时间点，不能把其中“等待页面修改”“main 保持原样”视为永久状态。随后按用户指令优化了发现、日历、追番新版呈现：缩短顶部间距、重排卡片信息、统一封面评分与图标、加入三张手写 SVG 页头装饰。追番/日历 focused widget 测试 7/7 通过，新版 Web 预览构建通过；目标范围分析 0 error/0 warning，发现页原有 2 条 info 保留。初始全量 378/7 是旧基线，本轮未重跑全量。

用户已要求以中文提交本轮修改并编写「我的」页面改造交接；后续入口、真实统计复用、路由与验收要求见 [交接文档](handoff-modern-profile.zh.md)。新的提交与工作区状态以实时 Git 为准。
