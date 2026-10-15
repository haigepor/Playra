# 规则管理与编辑器布局第二版

## 本次修改

| 文件 | 目的与影响 |
| --- | --- |
| `lib/bean/card/rule_card.dart` | 已安装来源采用站点、状态、SDK 页脚三个层级。只有传入 SDK 信息的管理卡片使用新布局，仓库等通用卡片保留原结构。 |
| `lib/pages/plugin_editor/plugin_view_page.dart` | 筛选操作收进统一工具栏；去掉重复 SDK 总览；已安装数量改为列表标题旁计数；SDK 身份仍来自登记映射。 |
| `lib/pages/plugin_editor/plugin_editor_page.dart` | 表单宽度与列表对齐；宽屏名称与版本并排，小屏单列；分类标签统一；测试采用描边，保存使用主色。 |
| `lib/pages/plugin_editor/editor_form_widgets.dart` | 统一分段选项圆角和选中状态；输入框使用细描边；保留控制器、语义与大字体换行。 |
| `lib/pages/plugin_editor/rule_management_widgets.dart` | 表单分区统一边框、标题字号和圆角，也影响规则测试页的同类分区。 |
| `lib/presentation/modern/pages/modern_player_detail_page.dart` | 修复构建发现的既有 `ShapeBorder.copyWith` 类型错误：仅对 `OutlinedBorder` 改描边，其余自定义形状保留。无播放流程改动。 |
| `test/rule_editor_layout_test.dart` | 覆盖 320 / 390 / 900 宽度及 1 / 1.6 字号的四分区切换、草稿保留和无布局异常。 |

沿用已有纸艺背景及 SVG，未增加生成图片、依赖或修改 SDK/接口配置。未提交 Git。

## 验证

- 设置基础与 SDK 分组测试：23 项通过。
- 播放主题回归：1 项通过。
- 新增编辑器测试与设置基础测试：26 项通过。与前述设置测试重复，合计不重复测试 30 项。
- 编辑器 3 个源文件静态分析无问题；规则列表与卡片无问题；播放页保留 2 条既有 if 括号格式提示。
- UTF-8 严格解码、无替换字符/BOM、差异空白检查通过。
- 管理页真实 Web：320、390、1440 宽度截图；可更新筛选得到 0 / 4 与空态，恢复后显示 4 / 4；点击来源进入对应编辑器。
- 编辑器最终 Web 构建通过（94.8 秒）；真实浏览器确认基本信息与搜索分区及 390 宽度截图。四分区切换和草稿保留的完整验证以 6 项 widget 测试为准。

未保存、更新、删除真实规则，未修改启用状态或排序；Android / iOS 真机未验证。HTML 设计稿属于前一版参考，最新效果以真实应用为准。

## 回退位置

修改前副本位于 `.dart_tool/rule-layout-v2-backup/`，文件名与原文件一致。工作区已有其他任务的改动，回退时只对照撤销本次布局及兼容修正差异，不应整文件覆盖并行更新。
