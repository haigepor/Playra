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
| 详情 / 播放 | 竖屏上方直接播放，下方显示线路、选集、收藏和作品信息。横屏使用同一播放器，右侧抽屉可换集 |
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
- 播放内核：`lib/pages/player/` + `lib/playback/playback_session.dart`，页面只通过 `PlaybackInitParams` 传入解析后的地址

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

当前工作区的 `flutter test` 在本机受 Windows 原生测试工具链限制，暂不作为门禁；首页与底部导航的 widget 测试位于 `test/`。

## 说明

- CliCli 相关密钥与设备参数属于第三方服务配置，仅用于本地开发，不应作为公开分发凭证；公开仓库前应移入本地私有配置。
- 内容版权归原服务与版权方所有，本项目仅保留客户端实现，不提供内容。
- GPL-3.0，见 [LICENSE](LICENSE)。播放器基于 Kazumi / media_kit 生态，相关版权归原作者。
