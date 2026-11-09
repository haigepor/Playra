# 播放器原生交互深查与修复

本轮修改 4 个产品文件、增加 1 个回归测试文件，并修正 2 个既有测试文件的过时控件定位。前两轮界面修改和用户已有子模块改动均保留，未提交或发布。

## 修复

| 问题 | 改动及影响 |
| --- | --- |
| 连续横屏、竖屏、返回可能并发完成 | `VideoFullscreenController` 按顺序提交平台请求，单次请求失败仍向调用者报错，但不阻断后续方向切换与退出；继续只占用一个路由历史项 |
| 画中画进入时重复点击或后台暂停 | Android 进入请求在首次异步检查前加保护；已经处于画中画时不重复进入；进入中或画中画内的 paused 事件不按普通后台规则暂停播放 |
| 画中画回调被已卸载页面清除 | 注册与释放增加页面所有者；旧页面释放不能移除新页面的回调 |
| 桌面画中画退出强制恢复固定尺寸 | 保存进入前的位置、尺寸、置顶、最大化和全屏状态；视频比例后到时更新小窗比例，不覆盖原始快照；离开播放页面也恢复窗口，且不重新进入已退出页面的全屏 |
| 低倍速或位置未推进时重复发送同秒弹幕 | 同一来源秒只发出一次；切换弹幕、切换全屏、加载新来源和卸载页面时使旧延迟任务失效 |
| 旧 UI 测试无法执行或定位不准 | 替换过时的 TextButton/FCard/FButton 定位；圆角控件边缘点击改为有效边缘的中点；关闭按钮定位避免同时匹配控件与其 Tooltip |

没有更改解码器、来源协议、持久化格式、SDK 密钥或正式构建清单。

## 已通过的验证

- 修改的 4 个产品文件与 3 个测试文件执行 `dart analyze`，结果 `No issues found`。
- 在 Windows 原生 Flutter 测试运行器中，5 个测试文件共 **26 项全部通过**：新增全屏/画中画/弹幕用例，以及缓冲覆盖层、播放器契约、公共控件、导航布局回归。
- 新增用例覆盖：慢平台请求期间连续切换横竖屏并返回；方向请求失败后仍能退出；旧页面不能释放新 PiP 回调；同秒弹幕去重及切换后代次失效；多次修改小窗比例后仍能恢复原窗口。
- 全屏路由和返回使用真实 Flutter 路由；系统窗口操作使用 MethodChannel 测试替身，**不代表真实系统旋转或窗口外观已验收**。
- 严格 UTF-8、BOM/换行约定、差异空白与修改范围检查通过。

此前执行不了的公共控件测试本轮已实际运行。首次运行发现过时的测试定位与圆角区域点击错误，修正后 26 项聚焦检查全绿；未删除用例或降低尺寸、文字颜色、业务回调断言。

## 原生测试环境与私有输入

正式工程的 `flutter test --no-pub` 仍在 hook 阶段报：

```text
Bad state: Lumina asset integrity mismatch: profile.json
```

本地 profile 摘要为 `1247afd6…`，当前正式清单要求 `81fafe71…`。其余四份原生库和压缩镜像均与当前清单匹配；不是 BOM 或 CRLF 导致的误差。当前提交记录说明 CI 已轮换到新的私有输入。用户提供的 SDK 关键字段与本地旧输入一致，并确认没有新 profile 或输入包。

按用户确认的隔离方案，测试工程位于 `.dart_tool/player-native-20261108/fixture/`。它使用历史提交 `a732690e` 的完整输入清单，当前旧 SDK 全部通过该清单 SHA-256 校验；构建 hook 原样保留，**没有关闭或绕过校验**。测试的 `lib/`、`test/` 连接到当前工作区，因此验证的是本轮代码。正式工程的清单、本地私有资产和 CI 配置没有修改。

这恢复了原生 Flutter 聚焦测试的执行能力，不能表示当前正式输入缺口已经解决，也不能表示新 SDK 的线上解析通过。

## Android 真机尝试：未运行到测试

检测到一台 Android 9 / arm64 设备，准备了独立包名 `com.predidit.kazumi.playerverify` 的系统交互样例。样例计划验证实际横屏、竖屏、进入 PiP 与退出回调；没有覆盖现有 Playra，也没有写入其业务数据。

构建在 Gradle 下载旧插件所需的 Kotlin / Android Gradle 依赖时失败，出现 Maven HTTPS 握手中断。按证据尝试了：独立工程消费现有本地代理、Kotlin 依赖仅从官方 Maven Central 取回、临时本地 HTTP 转发并由 Python 校验上游官方 HTTPS。部分依赖能推进，但 Gradle 仍出现 Google Maven 握手失败或本地连接拒绝，最终没有产出安装包。

临时转发已经关闭，独立工程中的仓库和代理设置已恢复；正式工程与全局配置没有改变。失败诊断保存在 `.dart_tool/player-native-20261108/gradle-network-diagnostic.log`，Android 样例保存在独立工程的 `integration_test/native_modes_test.dart`。

以下项目仍未验收：真实系统横竖屏转换、Android PiP 往返与系统按钮、桌面小窗的真实视觉表现、真实媒体解码、原生弹幕在视频上的连续渲染、退出小窗后的解码恢复。静态修复与测试替身不能替代这些结果。

## 复核与回滚

在本机隔离工程目录运行：

```powershell
C:/Users/haige/Desktop/Playra/.tooling/flutter/bin/flutter.bat test --no-pub test/player_native_modes_test.dart test/player_buffering_overlay_test.dart test/modern_player_contract_test.dart test/playra_components_test.dart test/modern_shell_layout_test.dart --reporter expanded
```

正式构建需恢复与当前 `inputs.json` 匹配的新私有输入；Android 系统验收还需可用的 Gradle 官方依赖下载链路。不能用旧输入摘要覆盖当前正式清单来制造通过。

本轮开始时的文件字节保存在 `.dart_tool/player-native-20261108/baseline/`，范围在 `scope.json`，增量在 `round3.diff`。回滚本轮使用该基线，避免回退前两轮或用户已有修改。
