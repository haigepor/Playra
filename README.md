# Playra

Playra 是基于 Kazumi 播放内核重建的 Flutter 跨平台动漫客户端。当前版本 `3.0.0+30000`，使用 Flutter 3.47.6。

Playra 接入 CliCli 单内容源。手机端使用发现、日历、追番、我的四个底部标签，平板使用侧栏。竖屏在视频下方选集，转为横屏后沿用同一集和播放进度。

## 页面与能力

| 区域 | 说明 |
| --- | --- |
| 发现首页 | 通栏轮播、分类、继续观看、播放历史与热播栏目 |
| 日历 | 按周查看更新时间，支持切换月份、上下周滑动、追番与详情跳转 |
| 追番 | 本地双列收藏，支持从作品或日历加入、逐条移除和确认清空 |
| 我的 | 主题、播放偏好、网络代理、本地数据与关于信息 |
| 搜索 / 分类 | 搜索以列表展示片名及元信息，分类使用可排序的三列海报网格 |
| 详情 / 播放 | 竖屏上方播放，下方显示线路、选集、收藏和作品信息；大尺寸横屏提供视频与选集双栏，显式全屏时可用侧边选集 |
| 播放器演示 | 公开 HLS 测试流，用于验证播放组件 |

## 架构

```text
main.dart
 ├─ 平台初始化：路径 / Hive / media_kit / window_manager
 ├─ bootstrapMediaSources() ──> CliCliSource
 │                              ├─ CliCliClient（Dio + esdk-v3 协议）
 │                              └─ EsdkV3（签名、加密、会话协商）
 └─ ModularApp ──> app_module.dart
                    ├─ /            ShellPage（发现 / 日历 / 追番 / 我的）
                    ├─ /browse      BrowsePage
                    ├─ /search      SearchPage
                    ├─ /detail      MediaDetailPage
                    ├─ /play        SourcePlayerPage
                    └─ /player      PlaybackDemoPage
```

- 数据源契约：`lib/features/sources/core/media_source.dart`（`MediaSource`、`MediaSourceRegistry`、`TtlCache`）
- 归一化模型：`lib/features/sources/core/media_models.dart`
- 唯一内容源：`lib/features/sources/clicli/`
- 存储：Hive `setting`、`playback_history`、`favorites` 三个 Box（`lib/services/storage/`）
- 设计系统：`lib/presentation/theme/playra_tokens.dart`（全局淡紫 token）、`playra_home_tokens.dart`（首页 / 日历页面 token）、`lib/presentation/widgets/playra_backdrop.dart`（共享背景）
- 播放内核：`lib/pages/player/` + `lib/playback/playback_session.dart`，页面只通过 `PlaybackInitParams` 传入解析后的地址。
- Kazumi 播放器控件：进度条及传输栏基于上游 [Predidit/Kazumi `906b144`](https://github.com/Predidit/Kazumi/tree/906b144fbc6abb40b83bccf86354ba1751c316e6) 适配，保留 Playra 的片源解析、历史和平台处理。当前不是完整的上游播放器：按当前产品选择暂不接入弹幕和一起看，不连接相关第三方服务。media_kit 与 media_kit_video 已同步到上游使用的 `484639a` 版本；Flutter 暂保留 3.47.6，原生播放仍需设备验证。

## 运行

运行 CliCli 内容源时，将 `tool/clicli/config.example.json` 复制为仓库根目录的 `.env.clicli.json`，填写有权使用的配置。Android 和 Web 启动脚本会读取本地文件。

```powershell
flutter pub get
flutter analyze
flutter run -d windows --dart-define-from-file=.env.clicli.json
flutter run -d chrome --dart-define-from-file=.env.clicli.json
```

Android 构建：

```powershell
.\tool\build-android.ps1 -AndroidSdk "D:/Android/Sdk"
```

产物位于 `build/app/outputs/flutter-apk/app-debug.apk`。

### GitHub Actions 的 Android 验证包

在仓库的 **Settings → Secrets and variables → Actions → Variables** 设置以下两个仓库变量。它们是 Playra 预留的公开客户端参数，填写前需与提供方的正式接入文档核对。

| 变量 | 填写内容 |
| --- | --- |
| `CLICLI_PUBLIC_CLIENT_ID` | 提供方为 Playra Android 分配、允许随应用分发的公开客户端标识 |
| `CLICLI_PUBLIC_SERVICE_URL` | 正式服务或自有授权网关的 HTTPS 基础地址，不含账号密码、查询串和片段 |

推送到 `main` 或推送 `playra/v*` 标签会触发 **Playra Android APK**。配置补齐后，可在 **Actions → Playra Android APK → Run workflow** 选择 `main` 重新验证。Android 作业会先列出缺失的变量，配置完整后运行 Flutter 测试、构建 ARM64 release APK，并核对包内的 `assets/playra/clicli-public.json`。成功后从 `playra-android-arm64-<提交 SHA>` 下载 APK。Web 作业独立运行。

该 JSON 是供后续授权适配器读取的发布配置，包内可见。正式接入还需要提供方给出设备注册或匿名会话流程、浏览和播放接口，以及账号或播放权限要求。服务端密钥留在服务端。当前 CI 使用项目已有的测试签名回退；如果提供方绑定包名和签名证书，还需为 `com.predidit.kazumi` 配置固定的签名证书并登记指纹。

验收时在干净的 ARM64 Android 设备上首次安装，检查首页能加载真实片单、详情能列出剧集，点播后出现首帧并持续播放。记录所测 APK 的提交 SHA。

## 目录

```text
lib/
├─ main.dart / app_widget.dart / app_module.dart / navigation.dart
├─ shell/                  四标签壳、侧栏、底部 Dock、基础主题
├─ pages/
│  ├─ discover/            首页、搜索、分类、共享媒体控件
│  ├─ calendar/            追番更新日历
│  ├─ detail/              媒体详情与选集
│  ├─ favorites/           追番收藏
│  ├─ profile/             我的与设置
│  └─ player/              播放器页面与组件
├─ features/sources/       MediaSource 契约与 CliCli 实现
├─ playback/               播放会话与全屏控制
├─ presentation/           设计 token、背景、通用控件
├─ request/core/           Dio 工厂与网络配置
├─ services/               平台、存储、网络、播放、日志
└─ utils/                  通用工具
```

## 验证

```powershell
flutter analyze
flutter build apk --debug --target-platform android-arm64
flutter build web --release
```

Windows 本机运行测试时，如遇 Visual Studio 探测的 `vswhere` 输出编码问题，可在当前 PowerShell 会话先执行 `$env:PATH="$PWD\.tooling\bin;$env:PATH"`，再运行 `flutter test --no-pub`。若 `flutter pub get` 提示插件需要符号链接，Windows 桌面构建需要系统提供符号链接权限（例如启用开发者模式）；仅验证 Android / Web 时，可在该进程设置 `$env:FLUTTER_WINDOWS='false'` 后解析依赖，这不验证 Windows 桌面构建。widget 测试不能替代真实设备上的解码、画中画和生命周期验证。

## 说明

- CliCli 相关密钥与设备参数属于第三方服务配置，仅用于本地开发，不应作为公开分发凭证；公开仓库前应移入本地私有配置。
- 内容版权归原服务与版权方所有，本项目仅保留客户端实现，不提供内容。
- GPL-3.0，见 [LICENSE](LICENSE)。播放器基于 Kazumi / media_kit 生态，相关版权归原作者。
