# 播放器平台边界与 Git 核对

## 目标与范围

按用户确认的范围，Web 接入 ArtPlayer，Android 及其他原生端保留 MioMedia 页面布局，复用原项目的播放内核与配置。现有 Bangumi 历史、收藏和弹幕身份不扩大到 MioMedia；来源作品不伪造 Bangumi ID。

本次为跨播放模块的 L 级工作，按研究、设计、实现、验证、审查推进。没有创建或修改 OpenSpec 变更。

改动范围：`web/index.html`、`web/player/`、`web/vendor/artplayer/`、`lib/services/player/source_media_player.dart`、`lib/services/player/web_player_surface*.dart`、`lib/presentation/modern/miomedia/miomedia_detail_page.dart`、`lib/pages/player/player_item.dart`、`lib/pages/player/player_item_surface.dart`、对应测试和本记录。此前 SDK 与环境配置改动另行保留。

## Git 证据

- 当前基线：`03f34604`。
- `adce00db` 之前已有原项目的 `PlayerItem`、`PlayerController`、`PlayerPlaybackController`，采用 media_kit/mpv 与自定义播放面板。
- `d44ca1a3` 接入紧凑播放详情页时，原播放器仍通过现有播放会话和 PlayerItem 使用。
- `4cd72909` 新增 MioMedia 独立详情页：直接 `Player()` + `VideoController(player)`，控件采用 `Video` 默认值；这和原项目使用完整播放配置的路径不同。
- `6f92193a` 继续调整 MioMedia 选集和播放状态，但没有把上述默认 Player 初始化接到原播放控制器。

原项目依赖的 media_kit 与 media_kit_video 同时固定在 Predidit/media-kit 的 `803c4a27912091db6f839d48d1b984a0d9f588c7`。本次不改这些依赖，也不修改原播放配置实现。

## 实现边界

### 原生平台

MioMedia 的媒体装载改由 `SourceMediaPlayer` 调用现有 `PlayerPlaybackController.createVideoController`。硬件解码、Android 渲染器选择、OpenSLES/AudioTrack、系统/应用代理、着色器、缓存策略、临时缓存目录和媒体资源释放由原实现管理。默认播放速度、日志级别也读取原设置。页面选集和暂停/就绪判定保留。

MioMedia 当前布局及默认控件保留，这是用户选择的范围；没有把整套 PlayerItem 手势/控制面板移入来源页。经典/新版 Bangumi 播放器在原生端仍走原组件。

### Web 平台

选用 ArtPlayer 5.4.0（MIT）。发布包通过 npm SHA-512 integrity 校验，浏览器资源、许可证和 SHA-256 清单保存在 `web/vendor/artplayer`，随 Flutter Web 构建分发；其他设备不需要依赖运行时 CDN。

ArtPlayer 的 `proxy` 选项复用当前 media_kit HTMLVideoElement。解码/HLS/MSE、请求头代理和选集会话仍由现有实现持有，ArtPlayer 提供暂停、进度、音量、倍速、画面比例、全屏、画中画及截图控件。通过无副作用的 customType 保留源地址；控件销毁不清空 media_kit 持有的 src，不重复创建 HLS 解码器。

MioMedia 和原播放页面的 Web 表面均接入。原页面保留弹幕画布和真实下一集回调，避免原生 Flutter 手势层与 DOM 控件争抢事件。

官方依据：

- [ArtPlayer 仓库与许可证](https://github.com/zhw2590582/ArtPlayer)
- [ArtPlayer proxy 与 customType](https://github.artplayer.org/document/en/start/option.html)
- [ArtPlayer 生命周期](https://github.artplayer.org/document/en/advanced/property.html)
- [Flutter HtmlElementView 生命周期](https://api.flutter.dev/flutter/widgets/HtmlElementView-class.html)

## 验证状态

- Flutter 全量测试：531 项通过；Web 后端：15 项通过。新增原生会话测试覆盖请求头传递、原控制器调用、取消清理和退出后的装载拒绝；Web 控件测试覆盖媒体所有权、状态保留、下一集回调和销毁。
- 分析器没有错误或警告，MioMedia 文件仍有 5 条未加大括号的 info。标准 Web 和新版预览 Web 均构建成功；Android debug APK 构建成功。
- Web 浏览器实测《唐朝诡事录之长安》第 1、2 集，1920×800，readyState=4，视频时间持续增长；暂停、恢复、1.5 倍速和下一集通过。390×844 页面无横向溢出；返回发现页后 ArtPlayer 实例与可见 video 数均为 0。
- Android 新 APK 已安装。自动检查在播放后遇到模拟器 ADB 离线，未取得稳定视频画面证据；用户随后明确反馈“安卓的我测试可以了”。Android 播放结果归为用户实测通过，不冒称自动验证通过。
- APK SHA-256：`40F2F16C0D1A07ECDE96017EA26FF0FD70F9EC9ABDD8615814DF4D17AE0859AF`。
- Web 部分 Bangumi 请求仍返回 502/ECONNRESET；MioMedia 实际播放成功，这项外部网络问题与播放器控件接入分开记录。画中画、系统全屏及截图控件已提供，但本轮没有完整验证这些浏览器权限功能。

## 回滚

原有文件的修改前副本位于本机忽略目录 `.tooling/player-integration-before-20261013/`。新文件可按上述范围移除并恢复这些副本；此前 SDK 导入、D 盘工具链及路径配置不在本次回滚范围。报告编写时尚未提交或推送，后续提交记录以 Git 历史为准。
