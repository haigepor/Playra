# 可执行位置与命令

命令中的 SHA、分支、工具链目录均为示例参数，必须从当前仓库/环境读取。

## 本地 Android

```powershell
./tool/build-android.ps1 -Release -JavaHome 'C:/path/to/jdk' -AndroidSdk 'C:/path/to/sdk'
```

读取 `build/app/outputs/flutter-apk/app-release.apk`，用 SDK aapt/apksigner 核验；另存到 `build/releases`，避免覆盖之前交付的产物。版本和 source SHA 写入独立 JSON 收据。私有 SDK 输入必须按 `docs/release/build-inputs.zh.md` 准备；不把 SDK 本体上传公开仓库。

## GitHub Actions

```text
gh workflow run release.yaml --repo haigepor/Playra --ref <branch> -f platform=ios
gh workflow run release.yaml --repo haigepor/Playra --ref <branch> -f platform=cloud
gh run view <run-id> --repo haigepor/Playra --json status,conclusion,jobs,headSha,url
gh run download <run-id> --repo haigepor/Playra --dir <artifact-directory>
```

也可调用 GitHub 插件提供的读取/下载工具，或已授权 REST `/repos/haigepor/Playra/actions/workflows/release.yaml/dispatches`，正文包含 ref 和 inputs.platform。不要把 token 放进命令参数、文档或 JSON 收据。

## iOS 包核验

```text
python tool/cloud_build.py verify-ios <unsigned-ipa>
```

build/ios/iphoneos 的 device `.app` 与 Simulator `.app` 不可混淆。Apple Silicon simulator 也可以是 arm64，所以必须同时检查 Info.plist 的 `CFBundleSupportedPlatforms=iPhoneOS`。

## 常见失败分类

| 现象 | 检查与处理 |
|---|---|
| 原 main 缺少刚改过的页面 | 比较本地/远端 SHA，推送获授权的完整功能分支并选择该 ref |
| workflow dispatch 404/422 | 默认分支是否已有该工作流；目标 ref 文件是否有 dispatch/输入；Actions 写权限 |
| 未配置安卓证书导致 iOS 无法构建 | 目标 job 与 Android 签名隔离，不能给 iOS 填安卓密钥 |
| 干净克隆截图 PathNotFound | 测试自己创建输出父目录，不能依赖忽略的本机文件 |
| Flutter 版本清单找不到架构 | 检查 setup action 的真实 manifest URL 与 pubspec，禁止直接升 SDK 掩盖问题 |
| Windows setup action 报 `yq not found` | 由 plan 解析固定 Flutter 版本并输出普通字符串，传给 flutter-version；不要把字符串再次 JSON 加引号 |
| Linux tray_manager 缺少 appindicator | 对照锁定版本的 CMake 与真实日志安装开发库；本项目 0.5.x 需要 libayatana-appindicator3-dev |
| Windows 只显示 build_hooks 汇总失败 | 读取失败 step 后的 hooks_runner stderr/native-build.log，定位下载或编译错误，不跳过原生资产 |
| media-kit 解包报 LZMA codec is unsupported | 使用支持 liblzma 的 Windows runner；本项目选择 windows-2025，先核对 tar --version，再以原生库真实构建验证 |
| macOS 包仍显示 Kazumi | 检查 Xcode target PRODUCT_NAME 覆盖、scheme 和 XIB module；以构建后 app/Info.plist 为准，不能只看 xcconfig |
| 附件下载后大小或 SHA 不符 | 拒绝交付，取得新的附件下载地址后重试并重新校验；不能把进程退出 0 当成完整下载 |
| CocoaPods 最低 iOS 版本冲突 | 读取具体 podspec/Flutter 最低要求，同步 Podfile 与所有实际 target，并跑新构建 |
| Xcode 缺少指定版本 | 查本轮 runner 清单与安装目录，不从历史记录假定路径存在 |
| `--no-codesign` 后没 IPA | 使用 device app 按 Payload 封装；验收结构、平台、架构及未签名状态 |
| 页面正常但影视接口不可用 | iOS/桌面运行服务配置与 SDK 在线状态单独诊断，不归因到页面切换 |
| 编译模式间 GeneratedPluginRegistrant 冲突 | 同一本地 checkout 的 Flutter 命令串行；先结束当前操作再重新生成 |

2026-10-14，Flutter 3.47.6 的真实 unsigned device 包最低 iOS 为 15.0。该 SDK 自动迁移旧 target，因此源工程的 13.0 不是有效兼容性承诺。每次以产物 Info.plist 和收据为准。

## 官方来源

- https://docs.flutter.dev/deployment/ios
- https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow
- https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event
- https://github.com/actions/runner-images
- https://github.com/subosito/flutter-action

版本敏感事实应每次查当前官方来源；这些链接不是对以后工具链版本的固定保证。
