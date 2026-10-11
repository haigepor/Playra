# 「我的」入口页面：公共样式与尺寸优化

日期：2026-10-11。项目：`C:\Users\haige\Desktop\Playra`。

## 实施范围

本轮完成公共样式基础、全部设置菜单，以及用户追加的「以我的页面为基准缩小字体和组件」调整。新版样式通过 `SettingsAppearanceHost` 局部承接；旧版使用原主题。切换主题时保持同一个路由子树，避免丢失输入草稿。

| 项目 | 本轮标准 |
| --- | --- |
| 页面标题 | 设置工具栏 22；旧页面的 headlineSmall 收紧为 20 |
| 卡片标题 | 16；列表主文字 14 |
| 说明文字 | 12，行高 1.5；按钮文字 13 |
| 列表图标 | 20；箭头 16 |
| 卡片 | 圆角 16，内容内边距一般 14–16 |
| 同步页图标 | 介绍图标 64 → 40；服务图标 56 → 36 |
| 规则页介绍 | 内边距 24 → 16，装饰图标 32 → 20 |
| 空状态 | 图标 88 → 48，保留响应式滚动 |
| 按钮 | 视觉高度收紧，保留 padded 触摸目标；测试实际布局高度至少 48 |
| 宽屏内容 | 设置、同步、关于的公共内容最大宽度 760 |

右侧设置值由「分走半行」改为按实际内容贴右，仅给长值限制最大宽度。窄屏大字体时，值移到下一行。系统字体缩放与 SafeArea 保留。

返回按钮统一为 20 尺寸 Lucide 细线左箭头：默认透明，36 尺寸视觉反馈采用圆角 10 的矩形，实际 padded 点击区域至少 48。悬浮和聚焦仅提供轻微反馈，原返回回调保留。

## 修改文件、用途和影响

| 文件 | 用途与影响 |
| --- | --- |
| [modern_settings_scope.dart](C:/Users/haige/Desktop/Playra/lib/presentation/modern/settings/modern_settings_scope.dart) | 新增主题作用域、字号、按钮与输入控件主题、图标映射；仅新版启用 |
| [modern_back_button.dart](C:/Users/haige/Desktop/Playra/lib/presentation/modern/settings/modern_back_button.dart) | 新版返回按钮，透明底、轻微圆角交互反馈 |
| [sys_app_bar.dart](C:/Users/haige/Desktop/Playra/lib/bean/appbar/sys_app_bar.dart) | 新版普通工具栏统一承接返回按钮，保留显式回调与原生窗口控制 |
| [settings_module.dart](C:/Users/haige/Desktop/Playra/lib/pages/settings/settings_module.dart) | 设置路由和独立开源许可证页承接主题 |
| [settings_page.dart](C:/Users/haige/Desktop/Playra/lib/pages/settings/settings_page.dart) | 菜单分组、工具栏和宽屏侧栏外观 |
| [settings_detail_scaffold.dart](C:/Users/haige/Desktop/Playra/lib/bean/settings/settings_detail_scaffold.dart) | 统一工具栏；宽屏根据内层返回栈显示返回按钮 |
| [settings_list.dart](C:/Users/haige/Desktop/Playra/lib/bean/settings/settings_list.dart) | 分组、图标、条目间距与右侧值响应式布局 |
| [content_section.dart](C:/Users/haige/Desktop/Playra/lib/bean/widget/content_section.dart) | 新版分组标题尺寸和缩进 |
| [split_list_row.dart](C:/Users/haige/Desktop/Playra/lib/bean/widget/split_list_row.dart) | 新版连续分组卡片；旧版分行圆角保留 |
| [tonal_card.dart](C:/Users/haige/Desktop/Playra/lib/bean/widget/tonal_card.dart) | 新版圆角与细边框 |
| [state_presentation.dart](C:/Users/haige/Desktop/Playra/lib/bean/widget/state_presentation.dart) | 新版操作按钮收紧，原回调保持 |
| [empty_state_widget.dart](C:/Users/haige/Desktop/Playra/lib/bean/widget/empty_state_widget.dart) | 新版空状态尺寸收紧 |
| [history_module.dart](C:/Users/haige/Desktop/Playra/lib/pages/history/history_module.dart) | 历史页承接新版主题、字体 |
| [download_page_module.dart](C:/Users/haige/Desktop/Playra/lib/pages/download/download_page_module.dart) | 下载页承接新版主题、字体 |
| [sync_settings_widgets.dart](C:/Users/haige/Desktop/Playra/lib/pages/settings/sync/sync_settings_widgets.dart) | 同步介绍、说明、内容宽度与反馈样式 |
| [sync_settings_page.dart](C:/Users/haige/Desktop/Playra/lib/pages/settings/sync/sync_settings_page.dart) | 服务卡片尺寸、标题和说明字号 |
| [rule_management_widgets.dart](C:/Users/haige/Desktop/Playra/lib/pages/plugin_editor/rule_management_widgets.dart) | 规则介绍、分区、输入框的新版尺寸 |
| [about_widgets.dart](C:/Users/haige/Desktop/Playra/lib/pages/about/about_widgets.dart) | 关于页面的新版条目间距、说明字号和内容宽度 |
| [modern_settings_foundation_test.dart](C:/Users/haige/Desktop/Playra/test/modern_settings_foundation_test.dart) | 新增 20 项布局、控件、返回、草稿与样式切换测试 |

未修改设置键、存储结构、同步协议、规则解析、下载调度或依赖版本。保留本轮开始前未提交的「我的」页面修改以及既有子模块状态。

## 验证证据

- DONE：52 项定向测试全部通过，其中本轮新增 20 项；覆盖 320/390/760 宽度、1/1.5/2 倍字体、选择菜单、开关、操作按钮、宽窄切换、下级返回与新旧样式切换后的草稿保留。
- DONE：对受影响的 16 个路径执行 Flutter 静态分析，无问题；说明字号与最后返回按钮调整的文件再次分析。
- DONE：Web 预览入口构建成功，服务端口 8933 健康检查成功。
- DONE：浏览器验收全部设置、外观菜单、同步页面，以及历史/下载的真实空状态。受验收页面控制台无新增错误。
- DONE：Android debug APK 构建成功，安装到 emulator-5554 并启动。此结果不代表所有入口已在安卓真机完整验收。
- DONE：UTF-8、无 BOM、无替换字符及 diff 空白检查；未改变控制面文件。

字号与尺寸优化阶段截图：[设置菜单](C:/Users/haige/Desktop/Playra/docs/verification/modern-settings-menu.png)、[外观菜单](C:/Users/haige/Desktop/Playra/docs/verification/modern-settings-theme.png)、[宽屏外观](C:/Users/haige/Desktop/Playra/docs/verification/modern-settings-desktop.png)、[同步卡片](C:/Users/haige/Desktop/Playra/docs/verification/modern-settings-sync-compact.png)、[历史空状态](C:/Users/haige/Desktop/Playra/docs/verification/modern-settings-history.png)、[下载空状态](C:/Users/haige/Desktop/Playra/docs/verification/modern-settings-download.png)。

最后返回按钮重设计截图：[新版返回按钮](C:/Users/haige/Desktop/Playra/docs/verification/modern-settings-back-button.png)。真实点击已返回「我的」页，控制台无新增错误。

本轮没有运行全项目测试，不将定向测试通过等同于整个项目零问题。

## 限制与后续

### 控件尺寸追加优化（2026-10-11）

- DONE：新版设置条目的开关绘制比例缩小至 80%，描边为 1dp；原有 48dp 点击区域、禁用状态和切换回调保留。
- DONE：新版滑动条改为 2dp 轨道、半径 5dp 的圆形手柄与半径 1dp 的刻度，保留 48dp 拖动区域和原数值、步进逻辑。旧版继续使用原控件尺寸。
- DONE：20 项设置基础测试通过；补充了直接点击开关、拖动离散滑块及触摸区域检查，覆盖 320/390/760 宽度与系统字体倍率 1/1.5/2。
- DONE：三个相关 Dart 文件静态分析通过，Web 构建成功；390px 浏览器实际截图确认尺寸，受检页面控制台无错误。UTF-8 与 diff 空白检查通过。
- NEXT：本次追加未重新构建、安装 Android，移动端触摸交互以 Widget 测试验证，原生实际效果待查看。

截图：[缩小后的开关](C:/Users/haige/Desktop/Playra/docs/verification/modern-settings-small-switches.png)、[缩小后的滑动条](C:/Users/haige/Desktop/Playra/docs/verification/modern-settings-small-sliders.png)。

追加改动仅涉及 `modern_settings_scope.dart`、`settings_list.dart`、已有设置测试与本报告；修改前逐字节备份位于 `.dart_tool/modern-settings-control-size/`，可按对应子路径恢复本次改动而保留此前页面优化。

- NEXT：历史、下载、规则的专属布局继续分批改造；本轮完成公共主题和尺寸，不代表原先梳理的 31 个页面均已重构。
- NEXT：部分旧 `KazumiDialog.show` 调用未传页面 context，仍可能使用全局主题；随对应页面改造补齐局部主题捕获。
- NEXT：浏览器检查时旧下载设置入口曾出现 `Unsupported operation: Platform._operatingSystem`。下载管理空状态通过；下载设置的 Web 平台兼容异常另行处理，不将其描述为已修复。
- NEXT：原生下载、登录同步与 Windows 运行完整验收。当前 Android 构建仍有既有 Gradle/AGP/Kotlin 未来兼容性提醒，本轮未升级工具链。

## 回滚

本轮改动前原文件逐字节备份在 [modern-settings-foundation](C:/Users/haige/Desktop/Playra/.dart_tool/modern-settings-foundation)，按相同子目录恢复上述原文件即可；新增作用域和测试另行移除。不要对整个工作区执行重置，以免覆盖先前「我的」页面工作。该备份属于本地 `.dart_tool`，执行 clean 前应另行保存。
