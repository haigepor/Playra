## Context

Android 原入口仅从构建参数读取外部服务 URL，不能独立使用 MioMedia。当前 Gradle/AGP 为 8.14.5/8.11.1，minSdk 24，现有包支持 ARM32、ARM64、x64。官方 Chaquopy 17 支持此 AGP，Python 3.11 保留三个 ABI。构建用 Python 3.11 仅安装在本次证据目录，不改系统 Python 默认值。

## Goals / Non-Goals

**Goals:** APK 内具备完整 SDK 与 Python 运行时；首次影视请求懒启动，持续复用身份；取消/超时和大小限制与 HTTP 相同；生成真实可核验测试包。

**Non-Goals:** 不修改 SDK 加密、播放凭证策略、身份派生或内部配置；不把密钥返回 Flutter；不迁移电脑端身份到手机；不更换 Web 服务或媒体播放器。

## Decisions

- Chaquopy 17 + Python 3.11，使用已有三种 ABI。只打包固定桥接模块、适配器和 vendor SDK，不安装第三方 Python 包。
- 使用 MethodChannel 和既有 JSON envelope，避免应用间可访问的本地 HTTP 监听端口。显式 RuntimeUrl 仍走外部 HTTP；Android 未配置地址时走原生，Windows 未配置仍失败，Web 保持同源默认值。
- Kotlin 在后台工作池懒启动 Python，固定调用 android_bridge 模块。最多四个工作线程与有限待办，不允许请求提供模块、脚本或文件路径。取消走独立通道，迟到结果不能回写已释放界面。
- Python 复用 MioMediaAdapter/MioMediaSdk 与 RuntimeContext，私有目录由 Kotlin applicationContext.filesDir 指定。每设备首次生成，后续重启读取；不使用清除/替换命令。
- 输入最多 32 KB、响应最多 2 MB、预算最多 60 秒、已实现操作白名单。错误码中性，Python 堆栈与 SDK 私有字段不会返回界面。
- APK 使用原包名与现有签名，核对 Python 三 ABI 库、SDK、16 条规则、界面默认新版和与以前测试包的签名一致性。

## Risks / Trade-offs

- [嵌入运行时增加体积与首次加载时间] → 懒启动、三 ABI 测试包；SDK 仍纯标准库，按内容请求启动。
- [CPU 算法受 Python GIL 约束] → 沿用四槽边界，不承诺线程带来算法线性加速。
- [客户端内置联调配置可被提取] → 不声称 APK 可以保密；仅使用已有默认联调配置，不打包电脑的 device.json，不输出或展示密钥。正式分配值仍待平台确认。
- [当前模拟器包安装 restorecon 异常] → 编译/包内容/桥接测试单独验收；不将编译成功冒充真实设备播放成功，交付用户真机测试。

## Migration Plan

用户覆盖安装保留 Hive 数据与现有设置；新增 Android 私有 SDK 身份独立于电脑服务。Web/显式外部调用无需迁移。回滚原文件使用 `.dart_tool/android-embedded-python-20261012/backup/`；新增桥接和 Gradle插件一起移除。

## Open Questions

Android 真机解码由设备验收；平台正式绑定值尚未提供，当前保持原联调值。

官方来源：[Chaquopy Gradle](https://chaquo.com/chaquopy/doc/current/android.html)、[Java API](https://chaquo.com/chaquopy/doc/current/java.html)、[版本支持](https://chaquo.com/chaquopy/doc/current/versions.html)。Context7 没有匹配的官方库，因此使用官方站点。
