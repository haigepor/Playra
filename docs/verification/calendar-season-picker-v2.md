# 季度选择器第二版与 Web 触摸高亮修复

日期：2026-10-11。本记录替代上一版选择器的视觉方案；旧版日历实现和数据适配保持原有逻辑。

## 原因与处理

浏览器实测 `html`、`body`、`flutter-view`、全屏 `flt-semantics` 的 `-webkit-tap-highlight-color` 均为 `rgba(51, 181, 229, 0.4)`。点击可将这个青蓝色覆盖到整屏语义节点。修复前运行透明高亮检查，得到 `TAP_HIGHLIGHT_NOT_DISABLED`；单独加入透明高亮 CSS 后，同一检查的非透明节点数变为 0。

Flutter 本地 SDK 的 `engine/view_embedder/style_manager.dart` 仅在 Safari 分支自动添加这一禁用规则；当前浏览器未得到该覆盖。按 [MDN 属性文档](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/-webkit-tap-highlight-color) 将公共 Web 入口的高亮设为透明，覆盖所有应用页面，不修改焦点、滚动和输入事件。

年份格子的悬浮方块来自此前 `yearOverlayColor`。选择器局部关闭悬浮/按压覆盖和涟漪，保留选中底色及键盘焦点。未将原生 Android 的 Material 反馈误当作 Web 浏览器蓝色覆盖。

## 重新设计

- 标题显示“选择放送季度”，副标题显示当前正在查看的季度。
- 上半部分常驻官方 `YearPicker` 年份网格，下半部分四季 2×2 网格同时显示，不再来回切换视图。
- 点击年份或季度只编辑草稿，不关闭面板、不加载数据；底部“查看 YYYY 年 · 季度”统一确认一次。
- “今年”定位年份，“当前季度”重置草稿；关闭或点击外部遮罩取消。
- 历史秋季切回尚在春季的今年时自动收敛到当前可选季度，未来季度不可选择。
- 加高弹层，内容目标高度 600、上限为视窗 84%，桌面最大宽度 460；沿用暗色与淡紫色主题。矮屏和大字体滚动主体，确认按钮固定，避开底部安全区。
- 快速重复确认只提交一次，避免重复切季请求。

## 文件与边界

| 文件 | 改动及影响 |
| --- | --- |
| `web/index.html` | 公共 Web CSS 禁用浏览器触摸高亮，所有构建入口共用 |
| `lib/presentation/modern/calendar/widgets/calendar_season_picker.dart` | 同屏年份和季度、草稿确认、快捷定位、固定底部及局部覆盖效果 |
| `lib/presentation/modern/calendar/modern_calendar_view.dart` | 仅季度弹层启用加高布局；普通筛选保留原滚动布局 |
| `test/calendar_season_picker_test.dart` | 草稿提交边界、未来季度、重置、重复确认、窄屏大字和矮屏 |
| `test/modern_calendar_view_test.dart` | 真实弹层取消/确认和物理视图安全区、横屏回归 |
| `docs/verification/calendar-season-picker-v2.md` 与对应截图 | 修复及交付证据 |

未增加依赖、未修改排期服务、控制器、发现页、旧规则、HTTP API、包配置或全局控制文件。修改前副本位于 `.dart_tool/calendar-season-v2/`，文件名以双下划线连接原路径。回滚仅恢复该目录的五个对应文件，保留工作区此前修改。

## 已完成验证

- PASS：先运行新交互回归，旧实现无法同屏显示年份，测试失败；实现后服务/控制器/选择器/视图/导航共 31 项通过。
- PASS：4 个代码与测试文件 `flutter analyze --no-pub`，No issues found。
- PASS：UTF-8 严格解码，无 BOM、无替换字符，`git diff --check` 无问题。
- PASS：包含 320 宽、1.5 倍字体、568×360 横屏、底部 24 安全区的 Widget 检查。

构建与真实浏览器结果在构建完成后补充。
