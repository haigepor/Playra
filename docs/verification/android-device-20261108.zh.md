# Android 隔离构建与真机验证

2026-11-08，本轮已在 LLD AL20（Android 9 / arm64）上完成独立验证包的构建、安装和系统交互验证。移除临时原生日志后再次通过，最终使用的 MainActivity 与正式工程逐字节一致。正式工程代码、私有输入清单、全局 Gradle/代理配置未修改。

## 真机结果

| 项目 | 结果 | 证据与范围 |
| --- | --- | --- |
| 独立 APK 构建与安装 | 通过 | 最终 assembleDebug 27.9 秒，ADB 安装 8.3 秒 |
| 弹幕实际绘制 | 通过 | 使用正式项目同版本 canvas_danmaku 的 DanmakuScreen，RepaintBoundary 像素检查确认白色弹幕实际出现 |
| 弹幕暂停与恢复 | 通过 | 暂停期间位置保持不变，恢复后位置继续推进；断言均保留 |
| 横屏与竖屏 | 通过 | 使用正式 VideoFullscreenController 和 DisplayModeService；实际窗口为 2280×1080 与 1080×2280，切换后弹幕尺寸及像素绘制继续正确 |
| 硬件返回退出全屏 | 通过 | 通过真实 Android BACK 事件退出全屏；路由仍保留，之后继续进入 PiP |
| 进入画中画 | 通过 | 系统返回进入成功，收到原生 onModeChanged(true) |
| 系统画中画弹幕按钮 | 通过 | 打开系统 PiP 菜单，点击真实 Turn off danmaku 按钮；收到 toggle_danmaku 回调，并更新按钮状态 |
| 退出画中画 | 通过 | 将同一 Activity 带回前台，收到 onModeChanged(false)，画面恢复并确认已清空弹幕 |
| 清理与隔离 | 通过 | 两个临时测试包均已卸载；原 com.predidit.kazumi 仍安装。测试未打开其业务存储 |

测试使用真实手机、Flutter 路由、Android MethodChannel、系统 PiP 菜单和弹幕渲染，不使用这几层的 mock。该工程没有包含 Lumina 或媒体解码器，未验证播放源解析、真实视频解码、完整 PlayerItem 生命周期或正式整包构建。弹幕的来源匹配、调度及同秒去重仍以此前独立测试结果为证据，本轮验证渲染、暂停恢复与系统按钮链路。

## 下载和构建问题的处理

1. Java/Gradle 直连官方 Maven 的 TLS 握手失败；临时 HTTP 回环转发也有连接失败。改用本地文件 Maven 仓库，复用 2140 份已有缓存，并逐批补齐缺失的 POM、模块元数据、JAR 与 AAR。Gradle 不再通过该网络链路解析这些文件。
2. 主要从官方站点取得文件；少数持续断开 TLS 的文件从 HTTPS 镜像补齐，并核对发布摘要。profileinstaller AAR 还与已有官方模块中的 SHA-256 一致。来源与摘要记录在 mirror-checksums.jsonl。
3. 全量隔离工程在 mergeDebugAssets 出现 Java heap space；限制并发后仍失败。因此保留失败证据，另建仅包含本轮待测接口及必要插件的专用工程，使用 3GB 堆、2 个 worker 与进程内 Kotlin 编译。
4. 该专用工程的 Android 原生 Activity 与正式代码一致；仅包标识、显示名称、构建仓库和资源预算为测试用途。独立包名最终为 com.example.kazumi，与测试工具识别的 namespace 一致，避免清理错误包。

本地 Maven 仓库和调试工具只存在于 .dart_tool/android-device-20261108/。正式仓库的构建配置和 SDK 输入校验均保留。

## 运行中发现并修正的问题

- 默认测试帧策略不连续渲染，恢复后的第一次取样仍在弹幕起点。改为 fullyLive，保留移动和暂停断言；随后在真实帧下通过。
- ADB 广播不能替代系统 PendingIntent 动作；没有放宽接收器权限。改为通过系统 PiP 菜单的真实按钮触发。
- UI 层级读取耗时超过菜单显示时间，旧坐标点击时菜单已隐藏。驱动先获取按钮位置，再重新打开菜单并及时点击。诊断记录随后确认原生接收、平台通道发送和 Dart 接收全部发生。
- 诊断日志仅临时加入独立工程，最终已移除并重新运行通过。未据此改动正式播放器逻辑。

## 证据与复核

- 结果摘要：`.dart_tool/android-device-20261108/result.json`
- 通过记录：`device-1794128941783041400-1.log`, `device-1794129217175617100-1.log`
- 真机测试源码：`.dart_tool/android-device-20261108/device-fixture/integration_test/native_modes_test.dart`
- 驱动：`resolve_build.py`、`device_controls.py`
- 原生临时诊断证据：`pip-native-diagnostic.log`
- 按钮动作记录：`device-actions.log`
- APK：`.dart_tool/android-device-20261108/device-fixture/build/app/outputs/flutter-apk/app-debug.apk`
- APK SHA-256：`70ccc214d987fa28727cb849990d25573c21758e7f7263ad70eb0eb3af4cfc80`，大小 76353004 字节

从项目根目录使用本机现有设备复核：

```powershell
python -X utf8 .dart_tool/android-device-20261108/resolve_build.py device
```

驱动首先确认测试包标识未被其他已安装应用占用，再安装和运行独立测试包，并由框架清理。验证包会执行测试流程，不是正式升级包。原有全工程的 SDK 新输入缺口、整包资源合并内存问题，以及真实媒体解码验收仍单独保留，不能由本轮隔离通过推断已经解决。
