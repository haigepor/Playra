## Why

用户需要安装 APK 后直接测试影视内容和播放，不应依赖电脑运行 Python 服务或填写局域网地址。现有 Web 同源 HTTP 桥接可继续使用，Android 需要将运行时和 SDK 一起打包。

## What Changes

- Android 集成 Chaquopy 17，内嵌标准库 Python 与原样 SDK；无 requests、numpy、Lua 等 Python 依赖。
- Flutter 默认通过固定平台通道调用应用内 SDK；显式配置外部运行地址时保留原 HTTP 路径，Web 保持同源调用。
- 按应用私有目录持久化身份，启动/旋转屏幕/进程重建均不主动替换设备。
- 后台执行、有限工作槽、取消与总预算；只开放既有操作，错误输出不含密钥、身份或媒体地址。
- 生成原包名、现有签名的真机测试 APK，核验内含 Python 原生库、SDK、16 条规则与最新界面。

## Capabilities

### New Capabilities
- `android-embedded-sdk`: 独立 Android SDK 调用、生命周期、身份与可验证 APK。

### Modified Capabilities
无；复用现有操作和 JSON envelope，不改来源身份或播放协议。

## Impact

Android Gradle、MainActivity 与专用 Kotlin 桥接、SourceRuntimeClient 平台分支及 Python 编排入口、测试和交付文档。Chaquopy 为 Android 运行依赖，MioMedia SDK 保持纯标准库且算法不变。不对 Web 服务器、账户数据、旧界面或来源规则做关联重构。
