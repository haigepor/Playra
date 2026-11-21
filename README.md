# Playra Shell

Playra 的空壳基线：保留应用骨架、平台能力和播放内核，移除全部已接入的数据源与页面。

当前版本 `3.0.0+30000`，基于 Flutter 3.47.6。旧的数据模型与 Hive 业务 Box 已重置，只保留设置。

## 现在包含什么

| 层 | 保留内容 |
| --- | --- |
| 启动与路由 | `main.dart`、`app_widget.dart`、`app_module.dart`、`navigation.dart`、flutter_modular |
| 存储 | Hive + `GStorage`；仅 `setting` Box，键名与旧版本播放器/主题设置兼容 |
| 平台 | 路径、窗口、显示模式、全屏、浏览器显示、文件系统、资源 URL、画中画 |
| 网络 | Dio 工厂、代理、系统代理、ECH 以外的通用网络配置、图片缓存 |
| 播放内核 | media_kit 封装、音频后台、音量/亮度手势、倍速、截图、超分辨率、DLNA、定时关闭 |
| 播放器组件 | `PlayerItem`、控制面板、传输条、手势、缓冲层、截图组件、键盘快捷键 |
| 设计基础 | `PlayraTokens` 颜色/间距/字号；`playra_controls` 控件库；forui 主题 |
| 空壳界面 | 四标签占位页（发现/日历/追番/我的）+ 播放器演示页 |

## 已经删除什么

- 内容源：Lumina（含 `packages/lumina_engine`、`assets/lumina_private`、原生库与 CI 私有输入）、红果、Whisklet、Bangumi、DanDanPlay 弹幕、trace.moe 识图、KazumiRules 规则引擎与插件商店。
- 页面：旧版 `lib/pages` 内容页、新版 `lib/presentation` 页面与组件实验室。
- 数据层：收藏、历史、下载、搜索历史、WebDAV/同步、Bangumi 同步、弹幕屏蔽；旧 Hive 记录不再读取。
- 依赖：Lumina 引擎、弹幕渲染、规则解析、WebView、图片选择、识图、Upgrader 等。
- 文档、测试和探针工具：与旧来源绑定的 111 个测试、217 份文档、Lumina/红果/Whisklet 探针。

## 运行

```powershell
flutter pub get
flutter analyze
flutter run -d windows
flutter run -d chrome
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
├─ shell/                  四标签空壳、占位页、基础主题
├─ playback/               PlaybackSession、选集模型、全屏控制
├─ pages/playback_demo_page.dart
├─ pages/player/           保留的播放器组件与控制器
├─ services/
│  ├─ platform/            路径、窗口、全屏、浏览器显示、画中画
│  ├─ storage/             GStorage + SettingsKeys
│  ├─ network/             代理、图片缓存、网络状态
│  ├─ player/              播放服务、音频、截图、DLNA、定时关闭
│  ├─ logging/ shaders/
├─ request/core/           Dio、网络配置、错误映射
├─ presentation/theme/     Playra token
├─ presentation/widgets/   播放器依赖的控件库
├─ bean/                   对话框与播放器用到的少量组件
└─ utils/                  通用异步、时间、设备、媒体工具
```

## 播放器演示

主界面右上角或“发现”页按钮进入 `/player`，使用公开 HLS 演示流
`https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`。

播放器通过 `PlaybackInitParams` 接收媒体，不携带任何来源身份：

```dart
await playerController.init(
  PlaybackInitParams(
    videoUrl: resolvedUrl,
    workTitle: '作品名',
    episodeTitle: '第 01 集',
    httpHeaders: const {'referer': 'https://example.com'},
  ),
);
```

## 接入新数据源

当前没有保留旧的 `ContentSearchProvider` / `SdkPlaybackProvider` 抽象。推荐按功能重新落地：

1. 在 `lib/features/<source>/` 定义该来源的真实模型与请求服务。
2. 在 `lib/app_module.dart` 注册列表/详情路由。
3. 详情页确认播放地址后，构造 `PlaybackInitParams` 并复用 `PlayerItem`。
4. 需要持久化时，在 `lib/services/storage/storage.dart` 显式新增 Box，不复用旧模型。
5. 新页面按 `ShellPage` 的四标签结构挂载，或新增独立模块。

## 验证

```powershell
flutter analyze          # 当前 0 issue
flutter build web --release
```

`flutter test` 在本机受 Windows 原生测试工具链限制，暂不作为门禁。

## 许可

GPL-3.0，见 [LICENSE](LICENSE)。播放器基于 Kazumi / media_kit 生态，相关版权归原作者。
