# 季度选择弹层组件改造记录

日期：2026-10-11。对应用户确认后的 YearPicker 方案，替代此前被否定的年份下拉设计。本记录补充 `modern-calendar.md` 中的历史基线，不表示用户已完成视觉验收。

## 已实施

- 使用 Flutter 官方 `YearPicker`，年份网格与四季选项在同一底部弹层中切换，不再显示悬浮下拉菜单。
- 主体高度保持一致，切换采用 180ms 淡入淡出；系统关闭动画时直接切换。
- 标题 16、年份 15、季度 14、月份范围 11，未选季度采用透明背景；选中项使用发现页的淡紫色。
- 年份选择只更新弹层草稿，点击季度才提交并加载数据；返回季度或关闭不会提交草稿。
- 保留年份左右切换、回到当前季度、未来季度禁用、当前年份向前 20 年的原有范围。
- 弹层沿用 SafeArea，桌面最大宽度 430；字号放大时增加主体高度。未新增包依赖。

## 文件、影响与回滚

| 文件 | 本次用途与影响 |
| --- | --- |
| `lib/presentation/modern/calendar/widgets/calendar_season_picker.dart` | YearPicker、同层切换、季度选项和关闭按钮 |
| `lib/presentation/modern/calendar/modern_calendar_view.dart` | 季度弹层入口、430 宽度限制与可选公共标题；其他筛选仍保留原标题 |
| `test/calendar_season_picker_test.dart` | 年份草稿、季度提交、禁用未来、320 宽大字体、主体高度验证 |
| `test/modern_calendar_view_test.dart` | 关闭年份草稿保持原季度的回归验证 |
| `docs/verification/calendar-season-picker.md` | 当前交付证据与限制 |
| `docs/verification/calendar-season-inline-*.png` | 手机、窄屏、桌面实际构建截图 |

代码及测试的修改前副本位于 `.dart_tool/calendar-season-inline/`，文件名用双下划线连接原路径。需要回滚时仅恢复上述四个对应副本，不重置工作区的其他修改。未修改排期服务、控制器、发现页、旧版页面、规则 API 或全局配置。

## 验证结果

- PASS：四个修改代码/测试文件执行 `flutter analyze --no-pub`，No issues found。
- PASS：季度选择与日历视图 6 项 Widget 测试。
- PASS：日历服务、控制器、季度选择、视图及新旧界面导航回归共 28 项测试。
- PASS：`flutter build web --no-pub --target lib/main_home_preview.dart --output build/modern-home-preview --no-wasm-dry-run`，128.3 秒完成。
- PASS：`flutter build apk --debug --no-pub`，42.3 秒完成，产物 `build/app/outputs/flutter-apk/app-debug.apk`。
- PASS：真实浏览器 430×880，季度与年份两个视图的主体都为 160 高，弹层内容高 334；2024 年草稿关闭后仍为 2026 年 10 月。
- PASS：提交 2024 年春季后显示对应历史列表，再点击“回到当前季度”恢复当前排期。
- PASS：320×844 年份网格和四季按钮均在弹层范围内；Widget 测试另覆盖 1.5 倍字体无布局异常。
- PASS：1280×900 桌面弹层宽 430，居中显示；浏览器检查期间 console Errors 0、Warnings 0。
- PASS：用户现有 `http://127.0.0.1:8933/#/tab/timeline/` 标签页已刷新并确认当前日历显示。

截图：`calendar-season-inline-quarters.png`、`calendar-season-inline-years.png`、`calendar-season-inline-320.png`、`calendar-season-inline-desktop.png`。

## 限制

- Android 已完成 APK 构建，本轮未在真机或模拟器上安装验收；原生安全区域与手势效果仍需设备确认。
- 构建报告 Gradle 8.14.5、AGP 8.11.1、Kotlin 2.2.21 将来版本支持变更的警告，本次未调整工具链。
- 视觉设计已实现并提供实际截图，最终观感由用户手动验收。
