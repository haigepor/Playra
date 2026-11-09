# Playra 全页面 Forui token 统一审查与实施

日期：2026-11-08。依据项目锁定的 Forui **0.27.7** 源码实施，没有升级组件库。

## 结论与覆盖范围

已把新版主题的所有权交给 Forui，公共控件使用真实 Forui 组件；页面自定义布局通过语义别名读取同一主题。保留品牌主色、用户选择的旧版配色、播放器专用对比色及业务布局。

完整扫描了 `lib/presentation/modern`、`lib/pages`、`lib/bean/widget`、`lib/bean/settings` 下的 **256 个页面及业务组件 Dart 文件**，并单独检查主题入口、公共控件与旧版导航。256 是源码文件数，不是页面数，也不表示逐页完成了真机验收。上游组件演示目录 `components/upstream` 和 Shadcn 展示页保留其演示内容。

逐文件的原始行号、候选项及修改后扫描结果在 [source-inventory.json](../verification/forui-token-20261108/source-inventory.json)。扫描命中是审查线索，不等于缺陷数量；多行写法也可能不被单行正则计入。

| 静态候选类型 | 修改前 | 修改后 | 处理方式 |
| --- | ---: | ---: | --- |
| 页面直接指定数字字号 | 66 | 0 | 统一使用对应的文字角色 |
| 页面直接指定数字圆角 | 89 | 0 | 统一使用 Forui 圆角对应的别名 |
| 直接颜色常量或白/黑等颜色 | 106 | 8 | 页面颜色改为主题或媒体 token；剩余为主题选色数据与验证码白底 |
| 直接 ShadButton / ChoiceChip / TabBar / ListTile | 13 | 0 | 改为公共 Forui 适配组件 |
| 单行内边距带数字 | 282 | 31 | 常用间距已命名；剩余主要为 0、空状态大留白和插画占位几何 |

## 原来为什么不统一

1. `PlayraTokens.dark/light` 自己定义整套蓝灰表面，`playraForuiTheme` 再覆盖 Forui 的颜色、字号、圆角、对话框和列表组，Forui 实际上不是样式来源。
2. `PlayraButton`、`PlayraIconButton` 虽然名字统一，内部却是 Material、InkWell 和透明度拼接。ghost 按钮也有独立底色、边框，禁用、悬停和按压各有一组数值。
3. 卡片、徽章、提示框、分割线和悬浮按钮重新实现了组件库已有的视觉；播放器还通过 `PlayraComponentScope(enabled: false)` 绕回 Material 控件。
4. 首页、搜索、资料、线路、画质和选集存在独立字号、圆角以及混合的 Shadcn/Material 控件。`PlayerDetailTabs` 又单独绘制选中指示器。
5. Android 13 以上的新版导航会切换到另一套原生组件，其 Kotlin 文本颜色和字号写死，无法随 Forui token 更新。
6. 发现实际行为错误：关闭动画会把 `PlayraSwitch` 替换成沙漏；字体主题桥接不完整时会导致 Material 输入框缺少基线，主题切换时又会因为 `inherit` 不一致触发动画异常。

## 统一后的主题关系

```text
playra_design.dart
  Forui neutral touch + 品牌主色 + 手机可读性设置
    ├─ FThemeData → Forui 控件
    ├─ PlayraTokens.fromForui → 自定义布局的语义别名
    └─ playraTheme → Material ColorScheme / TextTheme / 平台路由表面
```

`playraDesign` 是新版颜色、文字和组件样式的入口。颜色以 `FColors` 为准；普通组件的悬停、禁用、选中、焦点边框和形状由 Forui 处理。只保留以下集中调整：品牌 primary/primaryForeground、页签至少 48dp、底部导航标签使用 12px caption。

Material 文字桥接保留框架需要的完整属性，再合并 Forui 字体、字号、行高和颜色；显式使用 `inherit: false` 和 alphabetic 基线，兼容输入框及新旧主题动画。旧版用户配色继续作为 Forui 配色的输入，颜色与字体前景保持成对一致。

`PlayraSpace` 是应用布局间距扩展，**不是 Forui 原生提供的 spacing token**。Forui 0.27.7 的通用样式集中在 `FColors / FTypography / FStyle`；页面仍需要自己的栅格、最大宽度和内容间距。现在这些值集中管理，不再给每个按钮另造一套视觉。

### 文字、圆角和尺寸

| 用途 | 公共别名 | 对应 Forui 角色 / 规则 |
| --- | --- | --- |
| 页标题 | `PlayraType.pageTitle = 22` | display.xl |
| 标题 / 分区 / 条目 | title 20 / section 18 / item 16 | lg / md / sm |
| 正文 | body 16，行高 1.5 | body.sm |
| 标签 / 辅助文字 | label 14 / caption 12 | body.xs / xs2 |
| 极小媒体标记 | micro 10 | xs3；不用于常规正文或导航 |
| 控件 / 海报圆角 | control / poster 10 | borderRadius.md |
| 卡片 | card 14 | borderRadius.lg |
| 重点表面 / 弹层 | hero / overlay 18 | borderRadius.xl |
| 缩略图 / 指示条 / 品牌 | 8 / 4 / 22 | sm / xs2 / xl2 |
| 手机触控区域 | 至少 48dp | lg 控件及应用触控约束；文字放大时增长 |
| 页面常用间距 | 2 / 4 / 6 / 8 / 12 / 16 / 20 / 24 / 32 | 应用间距扩展；不覆盖组件内部状态色 |

常量别名用于 Flutter 的 const 布局；新增主题契约测试检查别名与锁定版本的 Forui 实际值一致，避免升级后静默漂移。

## 组件采用清单

| 场景 | 统一后的实现 |
| --- | --- |
| 主、次、描边、ghost、危险按钮 | `PlayraButton → FButton` 对应 variant |
| 图标按钮 | `PlayraIconButton → FButton.icon`，保留 tooltip、选中语义和 48dp |
| 日期按钮、线路、画质、筛选选项 | `FButton`；选择型控件统一 `PlayraChoice` |
| 卡片 | `PlayraCard → FCard`；可点击卡片使用 `FTappable` |
| 文本与表单输入 | `FTextField / FTextFormField`，保留 controller、IME、校验、只读等契约 |
| 开关、复选框、滑块 | `FSwitch / FCheckbox / FSlider` |
| 单选 | `FRadio` 负责视觉；已有 `RawRadio` 分组负责方向键与焦点契约 |
| 列表项与分组 | `FTile / FTileGroup` |
| 徽章、提示、分割线 | `FBadge / FAlert / FDivider` |
| 悬浮操作 | `FButton.icon` 或公共按钮，不再自绘阴影与状态色 |
| 展开项、菜单、对话框 | `FAccordion / FPopoverMenu / FDialog` |
| 页签 | `PlayraTabBar → FTabs`；调用者的 TabController/TabBarView 继续持有状态 |
| 新版底部导航 | `FBottomNavigationBar`；各平台统一使用该控件 |
| 选集按钮 | `FButton.raw`；播放标记、下载状态、长标题是自定义内容 |
| 加载 | Forui progress；关闭动画时只给加载提示提供静态替代，开关仍可操作 |
| 底部弹层 | 保留既有路由和键盘避让，表面复用 FCard，按钮复用公共控件 |

2026-11-09 原生复验后，底部导航已去掉玻璃背景采样，改为贴边 Forui 导航；平板按宽度切换为导航轨或 Forui 侧栏。页签统一为平直底线样式。新版壳层不再挂载硬编码原生导航，原生播放器、旋转和画中画逻辑没有因此改动。详见 [影视布局重构](cinema-redesign-20261109.zh.md)。

## 按页面族的检查与处理

| 页面族 | 已处理的样式与边界 |
| --- | --- |
| 首页、分类、榜单 | 统一卡片、标题、按钮和海报圆角；媒体渐变使用媒体 token |
| 搜索、搜索结果、以图搜番 | 输入、清空、提交、筛选及记录操作统一；保留查询和历史行为 |
| 日历、季度选择 | 日期按钮、筛选、卡片和排期标记使用统一 token |
| 追番、收藏、历史、下载 | 卡片、列表、展开和操作统一；保留真实记录和回调 |
| 我的、关于、日志 | 文字、间距、圆角收敛；装饰形状不再带独立颜色表 |
| 内容详情、作品资料、人物资料 | 标题、正文、标签、弹层入口及页签统一 |
| SDK / 传统播放详情 | 线路、画质、分段、选集、提示和资料页签统一 |
| 原生播放器附属页面 | 弹幕源筛选、选集/评论页签、弹层表面统一；媒体画面控件保留专用对比色 |
| 设置及全部设置子页 | 通过公共列表/表单组件统一；验证字号、返回、草稿和主题切换 |
| 引导、错误、来源不可用 | 统一正文、图标周围表面和操作按钮，保留可达的恢复操作 |
| 规则编辑、测试、目录 | 间距、圆角和输入操作使用公共入口；编辑/调试功能保持原有契约 |
| 旧版界面 | 用户配色与导航布局保留；公共控件、样式别名及 Forui 主题桥接共用 |

## 为什么还保留自定义实现

- **视频画面与海报遮罩**：任意亮度的画面需要固定对比，`PlayraMedia` 集中定义黑色画布、白色前景、边框及不同强度 scrim。不能把浅色页面的黑色文字直接叠到视频上。
- **业务状态色**：观看中、计划、看完、搁置、放弃、奖牌和成功/警告不全是 Forui 内置颜色角色，继续放在语义扩展中；危险操作和错误色取 Forui 对应角色。
- **海报比例、剧集网格、手势、弹幕**：属于媒体内容和布局机制。通用组件负责外观与交互，专用内容读取同一组 token；现代页面已移除玻璃折射装饰。
- **验证码页面白底**：是嵌入网页的显示要求；主题选色列表中的绿、蓝、紫是用户可选择的数据，不是页面私有调色板。
- **旧版导航、平台路由与窗口行为**：保留既有导航语义和平台能力，通过主题桥接消费颜色。此轮没有删除旧版入口，也没有更改用户保存的界面选择。
- **Shadcn 依赖与 Lucide 图标**：普通页面的 ShadButton 已移除；图标和上游演示仍使用现有依赖。没有为移除一个包改写展示页或替换整套图标资产。

后续新增自定义 UI 应优先读取 `FTheme.of(context)` 的颜色、文字、组件 style；确需 const 或媒体语义时，使用已有 `PlayraType / PlayraRadius / PlayraSpace / PlayraMedia`。不要在页面重新添加一套背景、边框、disabled/hover 透明度。

## 验证与限制

- 10 个公共组件、主题、设置、二级页、导航及播放器回归文件：**89 项通过**。
- 最后补充传统播放页签替换后，主题/控件契约文件再次运行：**12 项通过**，包括新增的两项 1x/2x 字号页签回调检查。与上一组有重叠，不把重复运行计为额外覆盖。
- 修复并复验：关闭动画的开关、主题切换动画、Material 输入框基线、两倍文字、1.6 倍文字导航舍入、横竖布局、底部安全区、页签点击/滑动同步、设置草稿与返回。
- 上述 Flutter 测试使用此前授权的隔离原生 fixture；当前项目的 lib/test 通过 junction 读取，未跳过原生 hook 校验。fixture 使用已匹配的历史 SDK receipt，不能把该结果表述为当前正式私有输入已恢复。
- 控件运行在 Windows Flutter 测试宿主；旋转与画中画状态测试使用平台通道测试替身，不能替代 Android 真机行为。
- Web 预览目标 `lib/main_home_preview.dart` 已构建；在真实 Chromium 390×844 页面操作了首页、搜索输入和频道切换、日历、追番、我的以及导航。48dp 操作区和底部导航位置可从语义树验证。
- Web 当前不支持 Lumina，静态预览服务器也没有 `/api/proxy` 后端；日历数据请求出现 404，第三方日志请求受 CORS 限制。记录了恢复状态与入口，不宣称在线内容或 Web 播放通过。
- 广域分析器结果无 error；保留已有的 3 条 SDK 播放页 warning 及历史 info，未关闭检查。
- **正式 Android 构建仍缺少匹配的私有 profile**。2026-11-09 已完成隔离 Debug 包构建和雷电原生样式复验，确认此前的内存错误与缺失依赖错误链展开有关，并补齐了隔离依赖；没有修改正式输入清单或校验。原生运行范围、137 项聚焦回归及未验证项目见 [雷电验证报告](../verification/emulator-ui-20261108.zh.md)。

截图：[首页 390px](../verification/forui-token-20261108/home-390.png)、[搜索 390px](../verification/forui-token-20261108/search-390.png)。测试、构建、分析器日志及修改前副本位于 `.dart_tool/forui-unification-20261108/`。回滚本轮修改应使用该目录的逐文件 baseline，保留此前未提交工作。

规范依据：[Forui widget style deltas](https://forui.dev/docs/guides/customizing-widget-styles)，以及本地锁定 0.27.7 的 FColors、FTypography、FStyle、FButton、FCard、FTabs 和 FBottomNavigationBar 源码。
