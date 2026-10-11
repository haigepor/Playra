# 移动端主 Tab 横向切换实施记录

更新：2026-10-11。项目：`C:/Users/haige/Desktop/Playra`。

## 结果与范围

- DONE：移动端新版「发现 / 日历 / 追番 / 我的」点击底部导航后按方向横移，时长 280ms，曲线 `easeOutCubic`；导航栏与安全区保持固定。
- DONE：已访问页面保留 Element、控制器、输入、筛选和滚动位置；首次访问才创建。跨多个 Tab 时不创建中间页面。
- DONE：快速反向点击从当前绘制位置接续；最后一次选择决定终点，重复点击当前 Tab 不重新加载。
- DONE：后台页退出焦点、读屏和点击命中，暂停内部 Ticker；沿用 `RouteVisibility` 通知「我的」页释放可见性相关订阅。
- DONE：URL、底部选中状态与系统返回同步；设置等覆盖页面继续使用标准路由，返回时恢复缓存页面。
- DONE：首页排期表与追番空状态「去发现」通过共享壳层切换，避免重建整棵根路由。
- DONE：减少动画时直接切换；桌面及旧版保持原路由方式。平台由主题对应的 Android/iOS 平台识别，未使用窗口宽度启用动画；新版可用性仍服从原有平台限制。
- NEXT：第一版通过点击切换；如需全页手指横滑，单独处理首页横向栏目和日历内部七日分页的手势优先级。

复杂度 L，按 Research → Design → Implement → Verify → Review 完成。本次仅实施已确认的导航改动，没有修改来源 API、存储模型、依赖与控制面配置。

## 实现选择

采用缓存页面的 `Stack + FractionalTranslation + AnimationController`，而不是四页连续 `PageView`：跨多个标签时只在当前页和目标页之间过渡，避免经过空白中间页、触发额外初始化，同时不增加与内部横向滚动的手势竞争。

页面 Widget 实例也缓存，动画帧只更新位置与外层可见性，避免每帧重建整页内容。缓存随新旧样式切换或根壳层释放，不作为永久数据库缓存。

当前 `flutter_modular 7.1.0` 的标准 `navigate` 会替换根堆栈；移动壳层通过现有 `ModularRouterDelegate.reportNestedLocation` 报告 Tab URL，保留根页面。此类未从包主入口导出，因此仅在壳层使用一次带说明的 `implementation_imports` 兼容导入。升级路由依赖时必须重新运行导航契约测试；未修改 Pub 缓存或第三方源码。

## 修改文件

| 文件 | 用途与影响 |
|---|---|
| `lib/pages/index_page.dart` | 接入可替换的移动页面工厂，旧入口仍兼容 |
| `lib/presentation/shared/tab_shell.dart` | 移动端策略、URL 上报、返回逻辑及样式切换恢复当前 Tab |
| `lib/presentation/shared/mobile_tab_view.dart` | 新增缓存与横向过渡；集中处理可见性和快速切换 |
| `lib/presentation/modern/modern_tab_pages.dart` | 复用现有四个页面与根模块业务对象 |
| `lib/presentation/modern/pages/discover_page.dart` | 排期入口使用主 Tab 切换 |
| `lib/presentation/modern/pages/library_page.dart` | 去发现入口使用主 Tab 切换 |
| `test/interface_navigation_test.dart` | 导航测试注入原有假页面，继续验证旧版兼容与真实首页 |
| `test/mobile_tab_navigation_test.dart` | 新增 8 项导航与动画契约测试 |

## 验证证据

- DONE：8 项新增测试与已有导航、我的、设置、追番、日历测试合计 **60 项通过**。覆盖中间帧位置、跨页懒加载、输入/滚动保留、快速切换、覆盖返回、系统返回、样式切换、减少动画、旧版和桌面行为。
- DONE：上述 8 个 Dart 文件静态分析无问题；UTF-8、无 BOM/替换字符、diff 空白检查通过。
- DONE：Web 预览构建成功（74.6s）；Android debug APK 构建成功（37.7s），已安装并启动于 `emulator-5554`。
- DONE：手机浏览器模拟环境（390×844、Android UA、触摸）真实操作四个 Tab，URL 分别同步到 `/tab/popular/`、`/tab/timeline/`、`/tab/collect/`、`/tab/my/`。动画中「我的」卡片标题 x=81.15，结束 x=37，底栏位置保持固定。
- DONE：手机浏览器切到周二后往返「我的」，仍显示「周二放送」；进入设置后返回「我的」内容一致。受检操作未出现 JS 页面异常。
- DONE：Windows 桌面浏览器即使宽度 390px 仍直接切换，标题在 80ms 与结束时 x 均为 37，未启用移动动画。
- DONE：Android 模拟器打开全部四个新版页面；捕获真实横移中间帧。日历选择周二后往返「我的」仍为「周二放送」，系统返回到发现，未叠加第二层主导航。

截图：[Android 过渡帧](C:/Users/haige/Desktop/Playra/docs/verification/mobile-tabs-android-transition.png)、[Android 我的](C:/Users/haige/Desktop/Playra/docs/verification/mobile-tabs-android-profile.png)、[Android 日历](C:/Users/haige/Desktop/Playra/docs/verification/mobile-tabs-android-calendar.png)、[Android 追番](C:/Users/haige/Desktop/Playra/docs/verification/mobile-tabs-android-library.png)、[Web 过渡帧](C:/Users/haige/Desktop/Playra/docs/verification/mobile-tabs-web-transition.png)、[Web 设置返回](C:/Users/haige/Desktop/Playra/docs/verification/mobile-tabs-web-profile-return.png)、[Web 日历](C:/Users/haige/Desktop/Playra/docs/verification/mobile-tabs-web-calendar.png)、[桌面直接切换](C:/Users/haige/Desktop/Playra/docs/verification/mobile-tabs-desktop-unchanged.png)。

## 限制和回滚

Android 实际验收使用模拟器，尚未测试安卓真机的帧率与内存；未重新构建 Windows。当前 Android 构建仍有既有 Gradle/AGP/Kotlin 的未来兼容性提醒，本次未升级工具链。

既有文件修改前逐字节备份在 `.dart_tool/mobile-tab-motion/`，按相同路径恢复即可撤回本次改动；同时移除本次新增的分页视图、页面工厂、测试和记录。备份保留了此前尚未提交的页面改动，不要执行整个工作区重置。执行 clean 前应另行保存备份。
