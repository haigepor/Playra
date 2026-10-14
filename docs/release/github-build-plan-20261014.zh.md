# Playra GitHub 构建与首页入口修复

基线 `ed0a36df`，远端 main `24e04806`。用户授权：检查仓库与 agents 页面，跑通未签名 iOS 包；安卓继续本地，其他平台使用 GitHub 构建；将实际验证后的流程沉淀为 Skill。追加：恢复首页顶部推荐、热门。

复杂度 L，AIDE-5 研究、设计、实现、验证、审查。修改范围：发布/质量工作流、必要的平台构建设置、打包/验证工具及测试、发布文档，截图测试的干净克隆修复，首页顶部入口及对应组件测试，新增的 Playra 专用 Skill。保留之前未跟踪分析文档与子模块状态，不上传私有 SDK 或签名凭据，不自动发布商店或 GitHub Release。

## 已确认

- GitHub 插件已连接 haigepor；仓库公开，具备维护权限；Actions 已启用。默认分支 main 未包含本地最近的搜索、播放器和 iOS 页面改动。构建必须指向包含这些提交的完整 SHA。
- `/agents?author=haigepor` 属于代理会话入口；当前浏览器返回 404，不能读取其中的会话状态。持续可复现的打包应由 `.github/workflows` 的 GitHub Actions 负责，不从 agents 页面是否可见推断构建状态。
- 远端只有质量和 Android/Web 发布工作流；没有 iOS job，Actions Secrets 列表为空。未签名 iOS 不依赖安卓密钥或私有 Python SDK；Android 内置 SDK 构建仍需相应输入。
- 最新质量 job `115265824908` 在 `content_skeleton_test.dart` 失败：未创建 `.dart_tool/content-skeleton-before-20261012` 就写预览图。必须修复测试自身，不能关闭测试或只在 CI 预建本机专用目录。
- `pubspec.yaml` 固定 Flutter 3.47.6，官方 macOS x64/arm64 发布清单均有对应版本。iOS 工程基线最低版本 13.0，需由真实 CocoaPods/Xcode 解析验证依赖的最低要求。
- Flutter 3.47.6 官方工具源码在 `--no-codesign` 时跳过 IPA 导出。采用 `flutter build ios --release --no-codesign` 得到 device `.app`，按 `Payload/Runner.app` 手工封装明确标记 unsigned 的 IPA，并验证结构、版本、架构和校验和。未签名产物不能直接安装到普通 iPhone。
- 推荐/热门逻辑未删除，但顶部仅展示四分类；两者藏在动漫子筛选且其当前状态会隐藏筛选。恢复为推荐、热门加四分类的顶部浏览入口，动漫子分类保留题材筛选。

## 计划与回退

1. 修复干净克隆截图测试与顶部推荐/热门，执行定向和全量验证。
2. 将云端平台构建与 Android 正式签名分离；从现有默认分支已注册的 release 工作流指定功能分支运行，不必为验收自动合并 main。
3. macOS runner 构建 iOS；Web/Linux/Windows/macOS 使用对应 runner 与实际依赖。每份附件包含 source SHA、版本、工具链和 SHA256。
4. 下载真实 run 附件，校验 iOS 包内容、签名状态和版本。构建成功不冒充真机播放验证。
5. 将确认过的命令、错误恢复、输入边界、验收和 near-miss 触发场景写入新 Skill，校验并打包。

回退只 revert 本轮提交；云端运行不会自动创建 Release，Skill 是新增目录，可移除新增目录回退。默认分支不强推或重置；请求 Skill 沉淀不授权修改全局 AGENTS/config 或记忆。

## 本轮已取得的证据

- 推荐/热门：修改前组件测试期望 6 个顶部入口、实际 4 个，复现失败；修改后首页与内容骨架 18 项定向测试通过。Web 390px 视口和 Android emulator-5554 实际展示六个入口，推荐/热门切换有内容；沿用现有 token 与 TabBar。Web 两条资源封面 502 属于当前服务可用性，未出现页面异常。
- Android：本地 Release 编译、APK CRC、内置 SDK、aapt 版本/ABI、apksigner v2、覆盖安装均通过。包为 `Playra-2.3.8-20308-1d1c86f6-home-tabs.apk`；测试签名，应用源码与后续 CI 修复版本一致，不能把包对应 SHA 改写成后续提交。
- 质量：远端干净 checkout 全量 Flutter 测试 **574 项通过**；SDK 输入 7 项、构建助手 6 项及 Web runtime 测试通过。原截图目录失败已在测试自身修复。
- [云端 run 38511916390](https://github.com/haigepor/Playra/actions/runs/38511916390)，完整源码 `844baab7f98221c1791baf4e0c379660f5491f4b`：iOS/Web/Linux/macOS 编译、封装与上传成功；Windows 原生资产失败，单独诊断修复。
- iOS/Web/Linux/macOS 四份附件已下载，外层 artifact digest 与内层 JSON 收据 SHA256、大小均核对通过。Linux 首次传输不完整被校验拒绝，重新下载后通过；不以下载进程退出码推断文件完整。
- iOS 实际 device IPA：2.3.8/20308，bundle `com.example.kazumi`，arm64，最低 **15.0**，无主应用签名/provisioning；Flutter 3.47.6、Dart 3.13.5、Xcode 26.2 build 17C52。SHA256 `ce1a76228406fb251231f0bb84be47d565ef7caed984c6a4a21b8d1422751471`。构建时 SDK 自动迁移旧 13.0 target，不能承诺 iOS 13/14。
- Linux：实际 ELF x86_64、可执行权限、lib 与 flutter_assets 齐全。Web：实际 index.html/main.dart.js 齐全。桌面编译未等同各平台启动/媒体播放验收。
- macOS 首份包为 universal arm64/x86_64，实际最低 12.0；附件核验发现 Xcode target `PRODUCT_NAME=Kazumi` 覆盖已有 Playra xcconfig。已移除覆盖并同步 product/scheme/XIB module，新增封装名称与版本门禁，重新构建后才交付更新包。

已恢复的 CI 失败：Windows Flutter setup 依赖缺失的 yq，改为 plan 解析版本后输出无引号普通字符串；Linux 当前锁定的 tray_manager 0.5.x 缺少 Ayatana 开发库，安装 `libayatana-appindicator3-dev`。不能据新版插件文档移除此旧版真实依赖。

Windows 单独诊断 run 38512858256 的 stderr 明确为 media-kit `tar: LZMA codec is unsupported`，不是影视解析或播放器 API 问题。更换为 windows-2025 并添加 LZMA 能力前置检查，保留原播放器及固定 checksum。macOS 品牌修复提交 d4ac701e，Windows runner 修复提交 1591ced2；新一轮五平台矩阵用于验证组合后的源码。

最新本地 Android 已在 `1591ced24ef6b56f50c4fa72daa998c1da87fb21` 重新编译，产物 `Playra-2.3.8-20308-1591ced2-home-tabs.apk`。SHA256 为 `15d4800ae1dd6ce8e16addaea3cc5b078ecbe4b33176dba4000208383fb3d5d3`，102607179 字节；与早期包字节一致，因为后续修改仅影响 CI/macOS/文档。覆盖安装后实际六个 tab 和热门榜单再次通过；package ID/签名/data 路径保留升级兼容。当前 Gradle/AGP/Kotlin 有未来兼容性提醒，本次构建成功，未为本任务升级工具链。

## Skill 与限制

版本化源 `skills/playra-platform-builds`，安装副本 `C:/Users/haige/.codex/skills/playra-platform-builds`；源与副本均通过 quick_validate，`.skill` 归档 CRC 通过。提供 3 项工作流验收案例和 8 正/8 负触发样例；触发边界是人工检查，未宣称完成量化 benchmark 或新会话发现验证。

本仓库 Secrets 当前为空。iOS/桌面没有 Android 内置 Python SDK 桥接；本次 runtime_configured=false，影视运行服务配置和签名后真机播放仍待单独验证。普通 iPhone 安装需签名；macOS 包未公证；Windows 包未做正式发行签名。默认分支没有合并，所有云端验收使用功能分支；[草稿 PR #1](https://github.com/haigepor/Playra/pull/1) 同时包含之前尚未推到 main 的新页面、搜索和播放修复。

## 修改文件与影响

| 文件 | 作用与影响 |
|---|---|
| lib/presentation/modern/home/modern_home_view.dart | 恢复两个浏览入口；四分类和页面 token 保持原有契约 |
| test/modern_home_view_test.dart、test/content_skeleton_test.dart | 覆盖六个入口/动漫筛选切换；截图测试独立创建输出目录 |
| .github/workflows/release.yaml、pr.yaml | 独立目标、质量门禁、各 runner 依赖、Windows 原生失败日志与附件上传；PR 也运行构建助手单测 |
| tool/cloud_build.py、tool/test_cloud_build.py | 选择平台、执行构建、封装、签名/架构/版本校验及边界测试 |
| macos/Runner.xcodeproj/project.pbxproj、xcshareddata/xcschemes/Runner.xcscheme、macos/Runner/Base.lproj/MainMenu.xib | 消除旧 PRODUCT_NAME 覆盖，同步产物引用和 Swift 模块；保留 bundle identifier |
| docs/release/build-inputs.zh.md、build-platforms.zh.md、github-build-plan-20261014.zh.md | 更新真实输入边界、命令、限制和本轮证据 |
| skills/playra-platform-builds/SKILL.md、references/platforms.md、evals/*.json | 版本化打包流程、失败分类与触发边界；全局仅新增同名安装副本 |

回退基线为 ed0a36df；本轮提交从 1d1c86f6 起，按顺序 revert 本轮提交即可，不 reset 用户代码。Skill 回退移除本轮新增的同名安装目录。此前未跟踪的两份分析文档和 dirty fastlane 子模块保持原样，未纳入提交。

## 官方依据

- [Flutter iOS 发布流程](https://docs.flutter.dev/deployment/ios)
- [GitHub 手动运行工作流](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
- [GitHub agents 会话管理](https://docs.github.com/en/copilot/how-tos/copilot-on-github/use-copilot-agents/manage-and-track-agents)
- [GitHub macOS runner 软件清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)

## 最终验收

[最终 run 38514041025](https://github.com/haigepor/Playra/actions/runs/38514041025) 全部五个云平台 job、plan 与 quality 成功，Android 云签名 job 按目标预期跳过。本地安卓与五份云包对应完整源码 `1591ced24ef6b56f50c4fa72daa998c1da87fb21`；之后的 PR 门禁、文档和 Skill 提交不改变应用功能源码。五份远端附件外层 digest、内层收据 hash/大小、归档结构均已在 Windows 下载后再次通过。

| 平台 | 文件 | 大小 MB | 产物检查 |
|---|---|---:|---|
| android | Playra-2.3.8-20308-1591ced2-home-tabs.apk | 102.6 | APK CRC、SDK、ABI、v2 测试签名、覆盖安装与六个 tab PASS |
| ios | Playra-2.3.8-20308-ios-unsigned-1591ced2.ipa | 32.6 | arm64 device unsigned；iOS 15.0+；版本、Payload、签名状态 PASS |
| web | Playra-2.3.8-20308-web-1591ced2.tar.gz | 25.0 | HTML/JS 及归档 PASS；本机新版页面交互 PASS |
| macos | Playra-2.3.8-20308-macos-1591ced2.tar.gz | 58.5 | Playra.app；universal arm64/x86_64；macOS 12.0+；名称、版本及架构 PASS |
| linux | Playra-2.3.8-20308-linux-1591ced2.tar.gz | 45.1 | ELF x64、执行权限、lib、assets PASS |
| windows | Playra-2.3.8-20308-windows-1591ced2.zip | 44.1 | PE x64、Playra.exe、Flutter/播放器/HTTP DLL、assets、CRC PASS |

本地 `build/releases/Playra-platforms-1591ced2.json` 保存六份收据，`Playra-2.3.8-20308-1591ced2-SHA256SUMS.txt` 提供统一校验。iOS 最新包 SHA256 为 `78db8226c608b49cb91906a24fd0cde8b5d37c7c79114d3813c9b14261b3103a`。Windows 实际 tar 为 bsdtar 3.8.4/liblzma 5.8.1，真实播放器原生构建已通过；没有改用其他播放器绕过失败。
