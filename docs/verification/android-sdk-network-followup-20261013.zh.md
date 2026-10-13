# Android SDK 网络错误与资源打包复查

## 当前状态

用户的红米 K50 / Android 15 在身份创建修复后显示 `UPSTREAM_UNAVAILABLE`，并确认 Wi-Fi 与移动网络均失败。仅凭该泛化提示，不能断言是运营商、端口或手机联网权限问题。当前 ADB 只有本机模拟器，没有连接用户真机。

本轮定位并修复了一个确定的资源打包遗漏，以及错误分类问题；真机恢复状态尚待新包实测。

## 确定缺陷与修复

### SDK 数据文件漏打包

`suite.py` 的 M6 原语读取同目录 `bf_tables.bin`，4168 字节。旧 Gradle 复制规则只纳入 `*.py`，前版 APK 的 `assets/chaquopy/app.imy` 没有该文件。

直接运行旧打包副本的 SDK 自检，在 M6 处返回 `FileNotFoundError: bf_tables.bin`；从旧 APK 字节码运行 M6 也能复现缺文件。现在固定纳入该文件，不改变 SDK 算法。

[Chaquopy 数据文件规则](https://chaquo.com/chaquopy/doc/current/android.html#data-files)支持按 `__file__` 相对路径读取自动提取的数据文件。安装本轮 APK 后，Android 实际提取路径中的文件大小为 4168 字节，SHA-256 与源码完全一致：`8db771263736ba4009df42755457a35af2554be0135f1d243be85d5eda392018`。

### 文件错误误报网络

原 `_execute` 将所有 `OSError`（包括 `FileNotFoundError`）归为 `UPSTREAM_UNAVAILABLE` 并重试。因此该提示不一定来自网络。

现在资源缺失单独返回 `SDK_RESOURCE_MISSING`，不进行无效网络重试。网络异常仅通过标准 errno 白名单细分为权限拒绝、网络不可达、连接被拒绝、连接重置、DNS 与超时，未知异常保留原错误码。界面显示对应提示，不输出原始异常、文件路径、代理配置、请求头或身份材料。

### 并发锁初始化

广泛回归时发现 Windows 多实例锁文件初始化标记写入存在竞争：另一个实例已经锁定字节区域时，标记写入可能失败。已经移除锁前标记写入，Windows 空文件字节锁直接验证成功；身份原子发布、重启复用、损坏身份保护等检查继续通过。

## 网络和平台证据

- Windows 固定 IP 的直接 TCP 连接成功，约 0.06 秒。
- 禁用所有 urllib 代理后，使用 SDK 与新身份请求真实目录成功，`hasVideos=true`。
- 这次请求对 `_bf_tables` 的调用次数为 0，因此不能以缺文件断言手机此次网络提示的根因；影响取决于实际服务端响应使用的算法链。
- 清单有 `INTERNET`、`ACCESS_NETWORK_STATE`，允许明文 HTTP；原生请求在工作线程执行。
- 默认接入点为数值 IPv4 `http://1.14.219.101:7090`，普通直连不涉及域名 DNS 或 TLS 证书。
- 模拟器在临时切换 `Enforcing` 后，输入和 ADB 回退命令超时。已通过雷电模拟器自身重启恢复，`getenforce` 再次确认 `Permissive`；没有清除应用数据或设备身份。这项正式策略对照未完成，不作为真机验证证据。

## 验证结果

- 运行时 Python 全部检查：44 项通过。
- Flutter 错误显示和运行桥接：21 项通过；定向分析无问题。
- 从最终 APK 读取并解出 SDK，以模块模式和独立字节码模式运行自检均为 `SELFTEST ALL PASS`；M6/套件 `7/7`，播放 `12/12`。
- 数据文件与源 SDK 原件逐字节一致；原 `suite/block/signature/device/transport/playback` 字节码不变。
- APK ZIP/嵌套 Python CRC、三种 ABI、16 份来源规则与装饰资产检查通过。
- Android 实际数据文件已提取并可读取，大小和 SHA-256 正确。
- 已覆盖安装并打开模拟器电影页，七天热播榜内容正常，没有 SDK 资源或连接错误提示。
- v2 签名通过，与前版测试证书一致，可覆盖安装。

## 交付

`build/releases/Playra-2.3.8-sdk-complete-20261013.apk`

- 大小：104,052,691 字节。
- SHA-256：`243c85a01f6f90a07fa646ef7cea8bdb1a6dc2557a043f4d253e48017aa79362`。
- 原身份与收藏、历史、进度继续保留；未引入第三方 Python 依赖、替代接入点或身份重置。

## 修改清单与回退

- `android/app/build.gradle`：纳入 SDK 固定数据文件。
- `tool/source_runtime/miomedia_adapter.py`：资源/网络错误分类，修正锁前标记写入竞争。
- `lib/presentation/modern/miomedia/miomedia_home_controller.dart`：具体错误提示与公共失败后的查询停止规则。
- `tool/source_runtime/test_miomedia.py`、`test/miomedia_home_failure_test.dart`：资源缺失、网络分类和提示回归测试。
- 本报告与 `.dart_tool/android-network-fix-20261013/`：包内 SDK 自检、安装包校验及源码备份。

回退仅恢复该目录中对应的 `*.before`，保留前几轮修改和其他用户变更。前版 APK 没有覆盖。

## 真机验收待完成

覆盖安装本轮完整包后，用同一设备分别重试目录；若仍失败，记录页面的完整错误码。新代码可区分 `SDK_RESOURCE_MISSING`、`UPSTREAM_PERMISSION_DENIED`、`UPSTREAM_NETWORK_UNREACHABLE`、`UPSTREAM_CONNECTION_REFUSED`、`UPSTREAM_CONNECTION_RESET`、`UPSTREAM_DNS_ERROR` 与 `TIMEOUT`。仍为 `UPSTREAM_UNAVAILABLE` 时，需要连接真机获取受限诊断证据，不能继续按网络类型猜测。

补充限制：`_execute` 包含本地 SDK 运算，`EACCES/EPERM` 也可能来自本地资源读取，因此权限错误码是定位线索，不直接证明应用联网权限被关闭。独立只读复核未发现阻断级问题。
