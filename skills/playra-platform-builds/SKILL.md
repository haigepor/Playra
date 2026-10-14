---
name: playra-platform-builds
description: >-
  为 haigepor/Playra 的 Flutter 项目构建、校验和交付安装包。用户要求打包 Playra、
  生成未签名 iOS IPA、通过 GitHub Actions 构建 Web/macOS/Linux/Windows、修复 Playra
  打包失败或核验构建附件时使用。Android 优先本地，其他平台优先远端对应 runner。
  不用于普通页面修改、其他 Flutter 仓库、GitHub agents 会话调度、应用签名或商店发布。
compatibility: Windows 本地 Android 工具链、GitHub 仓库写入/Actions 权限；iOS 使用 macOS/Xcode runner。
---

# Playra Platform Builds

## 目标与边界

将指定源码版本变成可追踪的构建产物，交付真实通过校验的附件及其限制。不要把工作流已启动、编译成功或取得视频地址等同安装和播放通过。

先读取仓库 `docs/release/build-platforms.zh.md`、`docs/release/build-inputs.zh.md` 和实际 `.github/workflows/release.yaml`。本文是流程入口，工作流和 `tool/cloud_build.py` 是可执行契约。版本、runner、run ID 和当前失败必须每次重新读取。

## 触发边界

- 适用：Playra 包、IPA、平台产物、GitHub Actions 云打包、安装包校验与构建失败。
- 不适用：仅调页面、业务接口逆向、其他 Flutter 项目、仅查看代理会话、证书申请、TestFlight/App Store 发布。
- 新建或修改流水线交给 `ci-cd-and-automation`；代码错误交给相应修复 Skill；签名与发布只在用户另行明确授权时处理。

## 1. 核对源码和授权

1. 验证当前仓库 `origin` 属于用户指定的 Playra 仓库，读取分支、HEAD、dirty 状态和 `pubspec.yaml`。
2. 记录所有预先已有文件和子模块变化。只提交本次任务文件，不上传忽略的私有 SDK、设备身份、签名证书、token 或 `.env`。
3. 优先 GitHub 插件检查仓库、工作流、job、日志与附件。插件未提供 dispatch 时，使用现有已授权的 gh/REST/Git 工具；缺少凭据时停下相应远端动作，继续本地检查。不要显示或重新存储 token。
4. 构建最新代码时比较远端 SHA，不能因为 main 能克隆就把它称为当前工作区最新版本。新增分支可以隔离构建，默认不强推 main、不自动合并 PR、不创建 Release。
5. 新工作流的 `workflow_dispatch` 需要默认分支注册。优先从已注册的 release 工作流选择目标 ref；每次通过实际运行返回值确认分支定义和输入生效。

## 2. 选择平台

| 目标 | 默认执行位置 | 产物与签名边界 |
|---|---|---|
| Android | Windows 本地 `tool/build-android.ps1` | APK；现有测试签名与正式签名明确区分 |
| iOS | GitHub macOS runner | device `.app` 封装为 unsigned IPA，不需要证书 |
| Web | GitHub Linux runner | 静态 Web tar.gz；服务端运行服务单独部署 |
| macOS | GitHub macOS runner | `.app` tar.gz；不把未公证包称为可无提示安装 |
| Linux | GitHub Linux runner | 应用 bundle tar.gz，保留可执行权限和依赖 |
| Windows | GitHub Windows runner | Release 目录 ZIP，包含 exe、DLL 与 data |

`platform=cloud` 选择上述五个云端平台，排除 Android。`platform=android` 或现有 release tag 继续走正式安卓云签名流程，缺少输入应明确失败。

## 3. 执行质量门禁与构建

1. 在修改前复现失败。干净克隆问题必须修复测试/脚本的输出目录准备，不禁用测试。
2. Flutter 版本跟随 pubspec；确认对应架构的官方版本可用。Apple runner 的 Xcode 与 CocoaPods 必须由真实 job 输出验证。
3. 远端质量门禁包括分析、Flutter 全量测试、构建工具与 SDK 输入单测、Web 运行桥测试。失败先看失败 step，再读取相关日志；不为绕过失败删门禁。
4. iOS 使用 `flutter build ios --release --no-codesign`。`flutter build ipa --no-codesign` 可能仅生成 archive 并跳过 IPA 导出，不凭命令名声称已经得到 IPA。
5. 用 `tool/cloud_build.py` 构建、封装和验证，不从日志抓取临时私有地址。构建助手不处理签名密钥。
6. 本地同一 Flutter checkout 的 test/analyze/pub-get/build 串行执行，避免插件注册文件与不同构建模式发生竞态。远端不同 workspace 的矩阵可并行。
7. iOS 当前没有 Android 内置 Python SDK 桥接。影视运行服务使用配置的 HTTPS 基址；空配置必须报告，不临时写入测试电脑地址。配置服务不等同真机播放测试。

## 4. 跟踪、下载和验证

1. 保存 run URL、完整 source SHA、各 job 结果、工具链和 artifact ID；轮询留出时间，在运行中继续独立工作并向用户更新进展。
2. 失败时根据现象分类：凭据/额度/runner、依赖/最低系统版本、SDK 编译、应用代码、封装/签名。修改对应层后验证新 SHA；不要反复重跑相同代码碰运气。
3. 下载真实附件，核验 SHA256 和 ZIP/TAR 内容。下载重定向时不把 GitHub Authorization 发送给不同域名，不记录带临时凭据的 URL。解包前拒绝路径穿越，必要时只在内存查看嵌套 IPA。
4. iOS 用 `verify_ios` 确认 Payload 下唯一 `.app`、Playra 名称、版本/build、iPhoneOS 平台、arm64 Mach-O、无主应用签名与 provisioning，并匹配收据 SHA。最低系统版本读取产物 MinimumOSVersion；SDK 自动迁移后不能继续按源工程旧 target 宣称兼容。
5. Android 核验包名、版本、ABI、签名、内置 SDK、CRC、覆盖安装；是否播放必须有实际媒体证据。
6. Web/桌面分别核验 HTML/JS、app/exe/bundle 以及依赖。编译通过仍不等于 macOS 公证、Windows 签名或所有接口在线。

## 5. 交付与沉淀

- 给出产物路径、Actions/PR 链接、SHA 和签名状态，列出 PASS/PARTIAL/FAIL/BLOCKED 的实际证据。
- 明确 unsigned IPA 还需签名才能安装到普通 iPhone；若只完成组件测试，不声称真机验证。
- 只把实际确认过的恢复步骤补入仓库文档/本 Skill，保留未通过项。未运行新会话加载检查时，说明安装后的 Skill 发现仍待新对话验证。
- 用户需要新一轮发布时重新读取源码与构建状态，不沿用旧 run/旧安装包。

## 参考与回退

详见 [平台命令与失败分类](references/platforms.md)。仓库 `skills/playra-platform-builds` 是版本化源，安装到 Codex Skills 的副本需从它同步；不改全局 AGENTS/config 来强制触发。新增 Skill 回退只移除本次新增目录；仓库改动 revert 对应提交；不会撤销已下载附件或用户数据。
