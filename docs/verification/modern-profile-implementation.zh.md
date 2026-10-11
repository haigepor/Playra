# 新版「我的」实施验收

日期：2026-10-11。项目：`C:\Users\haige\Desktop\Playra`。实施前 HEAD：`3ee8a34e`，保留 main 和现有上游关系。本次未提交或推送。

## 实施结果

- DONE：按个人观看手记设计实施深色页面，复用已准备的两张 SVG，空态和有记录时只展示对应一张。工具栏固定，内容单独滚动，最大内容宽度 760。
- DONE：直接展示共享 `MyController.watchStats`。番剧/集数沿用历史去重定义；离线数量是所有状态的任务数，不代表已完成下载或完播数。
- DONE：接入历史、缓存、规则快捷入口，观看偏好/数据与同步/应用三组现有路由，版本来自 `ApiEndpoints.version`。
- DONE：Bangumi 摘要区分验证中、未连接、异常、待验证、同步关闭、已开启；WebDAV 仅表达配置和开关。不在页面构建中验证账号或触发同步，不展示 token。
- DONE：按旧页模式成对调用 attach/detach，覆盖页面时释放统计监听，返回时刷新；控制器替换、应用恢复和卸载均有检查。新旧页共享控制器，不 dispose 共享实例。
- DONE：新版底栏四个 Tab 均为同一深色主题；顶部/底部安全区各消费一次。窄屏大字体快捷入口纵排，统计数字可缩小显示并保留完整语义。
- DONE：“去发现番剧”通过新增的 `TabDestinationScope` 调用现有壳层选择回调，浏览器实测只有一套底栏。

## 验证

使用项目 `.tooling/flutter/bin/flutter.bat`，未新增依赖、未升级工具链。

| 检查 | 结果与边界 |
| --- | --- |
| focused 测试 | 32/32 PASS：新版我的 16 项、既有导航/追番/日历 16 项 |
| 覆盖场景 | 320/390/760 宽度，1/1.5/2 字号，空态、长用户名和九位数字、横屏矮窗口、所有入口、安全区、统计去重、全部下载状态、新旧页切换、覆盖/返回、控制器替换与卸载 |
| 目标静态分析 | 6 个目标无 issue：profile 目录、页面、底栏、TabShell、my_module、测试 |
| Web 构建 | PASS，`lib/main_home_preview.dart` → `build/modern-home-preview`，最终源码构建 113.8 秒 |
| Web 运行 | PASS，8933 API health 正常；390/320/760 布局、发现 CTA、历史与界面设置返回、底部末项；最终刷新后 console 0 errors / 0 warnings |
| Android 构建 | PASS，assembleDebug 104.6 秒，`build/app/outputs/flutter-apk/app-debug.apk` |
| Android 安装 | PASS，在线模拟器 `emulator-5554` 上 `adb install -r` 成功，保留应用数据 |

截图：

- [390px 首屏](modern-profile-mobile.png)
- [320px 首屏](modern-profile-320.png)
- [底部入口](modern-profile-bottom.png)
- [760px 预览](modern-profile-desktop.png)

此前全量测试的 7 项失败属于既有记录；本轮仅对目标及相关导航/追番/日历做回归，未重新执行全量，也未降低其断言。构建提示既有 Gradle/AGP/Kotlin 未来兼容性警告，本轮没有升级。

## 文件及回滚

| 文件 | 用途与影响 |
| --- | --- |
| `lib/presentation/modern/pages/profile_page.dart` | 动态页面、共享控制器生命周期、只读同步摘要、状态栏 |
| `lib/presentation/modern/profile/modern_profile_view.dart` | 足迹、快捷入口、分组及响应式布局 |
| `lib/presentation/modern/profile/profile_sync_state.dart` | 可单独验证的只读状态文案 |
| `lib/pages/my/my_module.dart` | 新旧页面注入相同 MyController |
| `lib/presentation/modern/modern_shell.dart` | 四 Tab 的底栏深色一致，复用一次主题计算 |
| `lib/presentation/shared/tab_shell.dart` | 向子页面提供已有根 Tab 选择动作，不改变导航栈协议 |
| `test/modern_profile_test.dart` | 统计、状态、响应式、路由回调和监听回归 |
| `docs/handoff-modern-profile.zh.md` | 保留设计契约，纠正项目路径并更新实施状态 |
| 本验收文件及 `modern-profile-*.png` | 当前实现与运行证据 |

实施前逐文件副本在 `.dart_tool/modern-profile-implementation/`，代码基线 `3ee8a34e`。回滚仅恢复对应文件并移除本轮新增 profile 代码/测试/截图；恢复前核对后续改动，不能整体重置仓库。既有 submodule 脏状态未处理，既有测试重新生成的首页截图已恢复到本轮前内容。

真实账号同步成功、物理手机及厂商系统差异仍需对应环境验收；模拟器安装和 Web 空态不替代这些结果。
