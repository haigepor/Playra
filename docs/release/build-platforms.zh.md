# Playra 平台构建

Android 默认继续用本机 `tool/build-android.ps1`，Web/iOS/macOS/Linux/Windows 默认使用 GitHub Actions 的 **Playra platform build**。构建附件不会自动创建 GitHub Release，不自动签名 iOS，也不上传商店。

## 入口与版本

使用 `.github/workflows/release.yaml` 的手动入口，选择已推送且包含最新改动的分支。参数：`ios`（默认）、`web`、`macos`、`linux`、`windows`、`cloud`（五个云平台）、`android`（现有正式安卓云构建）。`cloud` 不请求安卓签名输入。

```text
gh workflow run release.yaml --repo haigepor/Playra --ref <branch> -f platform=ios
gh workflow run release.yaml --repo haigepor/Playra --ref <branch> -f platform=cloud
```

新建工作流要先存在于默认分支才能注册手动入口。本项目沿用已注册的 release.yaml，可选择功能分支验证修改后的定义。`playra/v*` tag 保留原 Android/Web 正式签名流程；Android 构建输入见 [构建输入](build-inputs.zh.md)。

## 阶段与产物

plan → quality → 各平台独立 build/package/upload。quality 不依赖私有 SDK；保留 Flutter analyze、全量测试、SDK 输入单测、构建助手单测和 Web 运行桥测试。任何门禁失败均停止后续构建。矩阵不因某一平台失败取消其他平台，便于分类修复。

| 目标 | runner | 输出 |
|---|---|---|
| iOS | macos-15 / Xcode 26.2 | arm64 device unsigned IPA |
| Web | ubuntu-latest | 静态资源 tar.gz |
| macOS | macos-15 / Xcode 26.2 | app tar.gz，不公证 |
| Linux | ubuntu-24.04 | x64 bundle tar.gz |
| Windows | windows-2025 | x64 Release ZIP，含 DLL/data |

Flutter 版本由 `pubspec.yaml` 固定。Apple 工具链实际版本输出到 job 与收据；必须核对本次运行，不从历史配置推断可用。附件名包含平台和完整 source SHA，文件名包含版本/build 与 SHA 短码；附件保留 14 天，重要包需及时下载保存。

Flutter pin 由 plan 中的 Python 解析后传给 setup action，不依赖各 runner 的 `yq`。Linux 当前锁定的 tray_manager 0.5.x 需要 `libayatana-appindicator3-dev`，不能套用新版插件已经移除这项依赖的说明。

Windows 旧 runner 的 tar 无法读取播放器 7z 包中的 LZMA，导致 media-kit build hook 失败。使用 windows-2025，并在编译前输出 tar 版本、检查 liblzma 支持；实际原生构建与附件校验仍是最终验收，不只依赖版本字符串。[Windows tar 文档](https://learn.microsoft.com/en-us/windows/tar/)

`tool/cloud_build.py` 负责目标选择、执行 Flutter、封装及产物验证。每份包旁有 JSON 收据和 SHA256SUMS，记录 source SHA、版本、架构（Apple）、签名状态、工具链、大小、hash 和 run ID。不记录服务地址或凭据。

## 未签名 iOS

`flutter build ios --release --no-codesign` 生成 device `.app`；工具按 `Payload/Runner.app` 封装 IPA。官方 Flutter 工具在 `flutter build ipa --no-codesign` 时会跳过 IPA 导出，因此不能仅看命令名字判断产物。

工具检查：Payload 唯一 app、Playra 名称、版本/build、iPhoneOS 平台、arm64 Mach-O、ZIP CRC、主应用无 CodeResources 和 provisioning。Apple Silicon Simulator 也有 arm64，平台标签不能省略。

```text
python tool/cloud_build.py verify-ios <downloaded-unsigned-ipa>
```

这是待后续签名的设备包，不能直接安装到普通 iPhone，也不是已经通过 TestFlight 或真机播放验证。

2026-10-14 实际产物的 MinimumOSVersion 为 **15.0**。工程基线写着 13.0，但固定的 Flutter 3.47.6 在构建时迁移 iOS target/Podfile 到 15.0；不能据此承诺支持 iOS 13/14。收据记录实际最低系统版本，不修改 plist 的字典格式版本来冒充系统版本。

## 来源运行服务

iOS 和桌面当前不内置 Android 的 Python SDK 桥接。需要影视接口时，在 Actions Secrets 配置可访问的 `PLAYRA_SOURCE_RUNTIME_URL`（仅 HTTPS 基址，无账号密码/query）。空配置仍可构建页面，但不代表影视接口可用。Web 使用同源服务桥，部署 Web 静态资源时还需部署相应服务。

SDK 本体、设备身份、密钥、证书和本机服务地址均不得写入公开源码、工作流日志或附件。签名正式发布是独立阶段。

## 本地约束与 Skill

同一 Flutter checkout 的 test/analyze/pub-get/build 要串行。否则开发/发布模式生成的插件注册文件可能互相覆盖。远端不同 runner workspace 可以并行。

版本化 Skill 位于 `skills/playra-platform-builds`，可安装到当前 Codex 的 Skills 目录。首次安装后的新会话发现需另外验证，不因创建文件就声称当前会话已自动加载。

## 实际验收记录

初次远端基线、失败原因与执行结果见 [2026-10-14 构建记录](github-build-plan-20261014.zh.md)。以实际 run/head SHA/job/artifact 为准；main、agents 页或旧附件的存在都不能替代最新产物验收。
