# Android 内嵌 Python SDK 测试包

## 交付

- APK：`build/releases/Playra-2.3.8-embedded-python-20261012.apk`，104012248 字节，约 99.2 MiB。
- SHA-256：`e915d3252cf0d264f7ecaa160452d036bd49c05f2d8bbcbfee4a1c7e68ca9094`。
- 包名 `com.predidit.kazumi`，版本 2.3.8 / 20308，Android 7.0（API 24）及以上。
- ARM32、ARM64、x64 三架构；v2 签名验证通过，与此前 network-playback-fix 测试包证书相同，可覆盖安装保留应用数据。
- 默认新版界面，包含最新选集布局、播放恢复、缓存与状态动画。

本次 APK 已内含 Python 3.11 与 MioMedia SDK。Android 未指定外部运行地址时，经固定平台通道直接执行 SDK，**无需电脑 Python 服务、无需局域网 IP、无需 adb reverse**。内容浏览与播放仍调用既有平台网络接口。

## 结构与边界

Flutter `SourceRuntimeClient` → `com.predidit.kazumi/source-runtime` → Kotlin 后台工作池 → `android_bridge.AndroidRuntime` → 原 MioMediaAdapter/MioMediaSdk。

原生平台不会启动 HTTP 监听端口。SDK 在首次内容请求时懒启动；身份位于 Android 应用私有 `files/miomedia/device.json`，首次创建、后续重启复用，不复制电脑上的身份，也不清除 Hive 收藏、设置或历史。

Web 保持同源 HTTP 调用；明确提供 `PLAYRA_SOURCE_RUNTIME_URL` 的原生构建仍沿用外部服务。Windows 未配置地址的失败行为保留。

固定路由/操作、32 KB 请求、2 MB 响应、最多 60 秒预算；四个工作线程与最多八个排队任务。取消走独立执行通道，避免排在慢请求后。Activity 释放后不回写旧界面。仅调用固定模块，不接受脚本路径、模块名或命令。

六个算法/播放 SDK 文件与现有 vendor 完全一致；没有引入 requests、numpy、Lua 或其他 Python 包。Chaquopy 是 Android 运行依赖；使用现有 SDK 联调绑定配置，正式分配值仍待平台确认。客户端包包含 SDK 配置，不能声称 APK 可以隐藏这些配置；设备秘密、会话材料与内部签名配置不会通过业务通道返回界面或写入本报告。

## 验证

| 检查 | 结果 |
|---|---|
| Flutter 桥接、外部 HTTP、取消、错误、Mio 页面与榜单/播放恢复回归 | 41 项 PASS |
| Python 3.11 运行层与新增原生桥接测试 | 37 项 PASS |
| Python 3.11 SDK 自检 | SELFTEST ALL PASS；playback 12/12 |
| 同一桥接模块真实内容/播放联调 | PASS：详情身份匹配、245 集、play ready；身份未变化，rotations=0 |
| Android release 构建 | PASS：首次 905.0 秒，最终复核 167.6 秒 |
| APK 内容与外层/内层 ZIP CRC | PASS |
| 三 ABI Python 库的 ELF 架构 | PASS：ARM32/ARM64/x64，与架构目录一致 |
| APK SDK 与入口 | PASS：11 个 SDK pyc、android_bridge.pyc、三 ABI 运行时与标准库 |
| SDK 源码和打包阶段副本 | PASS：suite/block/signature/device/transport/playback 字节一致 |
| 规则与新版功能标记 | PASS：16 个规则 JSON；三 ABI 中包含原生通道、新版界面、真实榜单模块和恢复标记 |
| Android 真机播放 | BLOCKED：当前 adb 仅列出 emulator-5554；已有隔离验收包曾报 restorecon 安装错误，未覆盖用户现有应用。本包交付用户真机验收 |

真实接口联调是在 Windows Python 3.11 下运行本次打包的桥接模块，不是 Android 设备执行。详情约 0.83 秒、剧集约 0.53 秒、播放换取约 4.04 秒；这些不能作为 Android 首帧速度承诺。`ready` 只表示 SDK 得到媒体地址，真机画面、声音和切集须单独确认。

榜单标题来自服务端，二进制完整性检查使用 `MOD_818368`；不能因 APK 没有硬编码“七天热播榜”字符串判断功能缺失。

## 真机测试

覆盖安装本次 APK，保持此前数据；无需启动电脑服务。检查电影/电视剧分类、七天榜单和搜索，再打开“吞噬星空”等作品，测试选集、切线、失败后恢复、暂停/缓冲标记与重启后的持续使用。不要先卸载旧包或清除数据。

## 修改与回滚

| 文件 | 作用 |
|---|---|
| android/settings.gradle、android/app/build.gradle | Chaquopy 17、Python 3.11、固定 SDK 文件打包与三 ABI |
| android/app/src/main/kotlin/com/example/kazumi/SourceRuntimeBridge.kt | 懒启动、后台调度、取消与安全结果 |
| android/app/src/main/kotlin/com/example/kazumi/MainActivity.kt | 通道注册/释放 |
| lib/services/source/runtime/embedded_runtime.dart | 固定 JSON 原生调用与取消 |
| lib/services/source/runtime/source_runtime.dart、runtime_endpoint.dart、runtime_endpoint_web.dart | 原生默认调用、HTTP 兼容与统一解析 |
| tool/source_runtime/android_bridge.py | 固定操作、私有身份目录、预算与输出过滤 |
| tool/source_runtime/test_android_bridge.py、test/embedded_runtime_test.dart | 新增边界验证 |
| openspec/changes/embed-android-python-sdk/ | 当前独立变更与验收要求 |

原文件备份与安全核验记录位于 `.dart_tool/android-embedded-python-20261012/`；回滚文件在其 `backup/`。新增桥接和 Gradle 插件须一起回滚；SDK 源码未改。先前播放恢复功能与用户既有改动不回退。

构建用 Python 3.11 位于同证据目录的 `build-python/`，仅构建时设置 `PLAYRA_BUILD_PYTHON`，没有修改系统 Python 默认值。首次构建下载的 Chaquopy 运行依赖位于正常 Gradle 缓存。

官方参考：[Chaquopy Gradle](https://chaquo.com/chaquopy/doc/current/android.html)、[Java 调用](https://chaquo.com/chaquopy/doc/current/java.html)、[版本与 ABI](https://chaquo.com/chaquopy/doc/current/versions.html)、[开源许可](https://chaquo.com/chaquopy/license/)。
