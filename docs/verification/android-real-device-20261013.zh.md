# Android 真机内容加载失败核查（2026-10-13）

## 结论与证据边界

当前 APK 内置 Python 运行时与 MioMedia SDK，Android 默认不连接电脑上的 Python 服务。SDK 在手机本地完成签名、加解密，再请求平台提供的数据。SDK 默认接入点是 `http://1.14.219.101:7090`，路径前缀为 `/api/v1/app/client`。

用户设备为红米 K50 / Android 15，移动网络下目录加载失败。当前 ADB 仅连接 Android 14 / x86_64 模拟器，没有连接这台真机。不能根据模拟器成功判定 ARM64 / Android 15 的运行正常，也不能仅凭移动网络信息认定运营商限制。

## 调用链

`MioHomeController → MioMediaService → SourceRuntimeClient → MethodChannel → SourceRuntimeBridge → android_bridge.AndroidRuntime → MioMediaSdk → SDK Client → 平台接口`

- `discover_page.dart` 创建默认 `MioMediaService()`，没有传入外部运行服务地址。
- 原生平台的 `PLAYRA_SOURCE_RUNTIME_URL` 默认为空，选择应用内 MethodChannel。
- 清单已有 `INTERNET`、`ACCESS_NETWORK_STATE`，且允许明文 HTTP；不存在遗漏这两个权限或禁止 HTTP 的配置问题。
- 私有设备身份位于应用内部目录，每次启动复用，不随普通请求重置。
- 最新 UI APK 已验证包含 ARM32 / ARM64 / x86_64 Python 库与 SDK，没有打入电脑的 `device.json`。

## 已复现并修复的问题

1. 目录与热搜公共入口都发生连接错误后，首页仍追加四次分类搜索。修改前回归测试实际记录六次操作：`catalog, searchConfig, search, search, search, search`。
2. 控制器丢弃异常，首页和分类页只显示泛化的失败文案，无法区分网络不可达、超时、运行时启动失败或身份读取失败。

现在仅当两个入口都失败、错误码一致且属于明确的公共网络/运行错误时，停止追加分类搜索。空目录、单入口失败、接口不存在等情形仍保留原有搜索兜底。

界面展示安全错误码与对应提示，重试开始后清除旧错误。不会展示异常原文、响应体、会话密钥、设备身份或凭证。没有修改 SDK 算法、平台地址、设备身份或播放策略。

## 验证

- 修改前重复查询测试失败：实际 6 次，期望 2 次。
- 修改后 Flutter 21 项检查通过，覆盖错误提示、重试恢复、接口失败兜底、单入口成功、分类分页、骨架屏与内置桥接。
- 定向 `flutter analyze --no-pub`：无问题。
- Python `test_android_bridge`、`test_miomedia`：19 项通过。
- 在 Windows 上使用相同 Android Python 桥接，从临时新身份请求真实目录：成功，约 1.2 秒，返回 `success/message/videos/pageinfo`。这是桌面链路证据，不等同于 ARM64 真机证据。
- 三个修改文件与本轮备份逐行对比，改动只涉及错误保留、提示与重复请求控制。
- Release 构建成功，约 127.8 秒。诊断 APK 为 `build/releases/Playra-2.3.8-network-diagnostic-20261013.apk`，104,044,807 字节；SHA-256 为 `9212966fda1add5e97e7e111017f7db21b6a9fdd93b1413200f129c9f5f567d4`。
- APK 的 ZIP/嵌套 Python 包完整性、三种 ABI 的 Python 库、SDK 打包源码一致性、16 份规则与装饰资产均通过校验；三个 ABI 中均包含新失败提示方法。
- v2 签名验证通过，与上一版相同证书，支持覆盖安装。证书 SHA-256 为 `fa4ec0e036ba5760beaab14bed70e1f6d625462317b8a42d828ac7c3797927fe`。
- 新 APK 已通过 `adb install -r` 覆盖安装到 Android 14 / x86_64 模拟器并启动。实际点击电影 tab 后，推荐作品「完美世界」与榜单前三「唐探1900」「毒液：最后一舞」「一路向西」显示正常。现场截图为 `.dart_tool/android-real-device-20261013/emulator-movie.png`。没有清除应用数据或重置设备身份。

## 真机下一步

安装本轮诊断 APK 后，在相同移动网络下重试并记录页面上的错误码；再用同一设备的 Wi-Fi 对照。`UPSTREAM_UNAVAILABLE` 或 `TIMEOUT` 指向连接/请求问题，`RUNTIME_UNAVAILABLE` 指向内置入口/原生加载问题，`IDENTITY_ERROR` 指向本地身份读写问题。`RUNTIME_ERROR` 仍需要更细的运行证据。

没有真实错误码和网络对照结果前，真机故障根因与恢复状态均为待确认。

## 修改与回退

- `lib/presentation/modern/miomedia/miomedia_home_controller.dart`：保留安全错误码，减少公共失败后的无效查询。
- `lib/presentation/modern/miomedia/miomedia_browse.dart`：首页失败提示包含错误原因与安全码。
- `lib/presentation/modern/miomedia/miomedia_category_view.dart`：分类空态显示同一错误原因。
- `test/miomedia_home_failure_test.dart`：六项针对故障分支与恢复行为的回归测试。
- 修改前源码备份：`.dart_tool/android-real-device-20261013/*.before`。需要回退时仅恢复这三个文件，保留此前其他改动。
