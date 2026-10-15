# Playra SVG 风格参考研究

核查日期：2026-10-15。范围：只研究官方图形规范与素材来源，不调整运行时、接口、依赖或业务页面。本文件补充 [全页面样式审查](full-page-style-audit-20261015.zh.md)。

## 1. 结论与用户参考

用户已明确选择的方向是：**粗圆描边、浅紫块面、实心播放三角、大四角星**，接近当前精选 `curated` 图标；不要细线日历、连接节点、复杂轨道或幼稚角色插画。

我们的设计判断：以 **Phosphor Duotone 的前后景分层思路**作为主要参考，用 **Fluent 2 的圆角、端点与视觉重量原则**保持整组一致，用 **Material Symbols 的填充与光学尺寸方法**检查小图可读性；空态采用 **Carbon 的内容优先原则**。这不是四套图标混装，而是用一套 Playra 原创图形落实用户选定的方向。

以下“官方事实”来自实际打开核查的一手资料；“Playra 建议”是结合当前页面和用户参考得出的设计判断，不代表这些设计系统的官方要求。

## 2. 四种参考的比较

| 参考 | 已核实的官方事实 | 与用户参考的关系：我们的判断 | 适用位置 / 不宜照搬处 |
|---|---|---|---|
| Phosphor Duotone | 官方 core 仓库按 weight 提供 SVG；Duotone 的字体实现由前景与背景层叠加。[官方 core](https://github.com/phosphor-icons/core) | 最适合借鉴“清楚主体＋浅色底块”的层次；粗圆描边、紫色和星形比例仍由 Playra 自定 | 栏目图标、简洁空态；不能认为所有现成图都已经符合用户参考 |
| Fluent 2 iconography / shapes | Regular 用于常规操作识别，Filled 可强调选中或提高小图重量；形状由 form、radius、stroke 定义，端点与笔画尺寸需要保持一致。[图标规范](https://fluent2.microsoft.design/iconography/)、[形状规范](https://fluent2.microsoft.design/shapes/) | 适合学习成熟、简洁、圆润的轮廓，避免“每张图都像不同作者画的” | 导航/状态/控件可借鉴；其系统图标要求单色，不可把 Playra 双色装饰称作 Fluent 官方规范 |
| Material Symbols Rounded | 官方仓库列出 Outlined、Rounded、Sharp 三类；Fill 可得到实心状态。指南说明 weight 影响粗细，optical size 用于不同显示尺寸的视觉调整。[官方仓库](https://github.com/google/material-design-icons#material-symbols)、[官方指南](https://developers.google.com/fonts/docs/material_symbols) | 适合校准播放三角、关闭、返回等小图；帮助避免大图直接缩小时细节堵塞 | 控制图标、小尺寸符号；Symbols 并没有官方双色款，双色仍是 Playra 自定处理 |
| Carbon empty states | 空态图片是可选、非交互的；内容要解释当前状态和下一步，空间有限可只用文字，多空态并列也应避免反复插画。[官方空态规范](https://www.carbondesignsystem.com/building-blocks/core/patterns/empty-states) | 提供装饰使用边界，不是一套要复制的紫色图形风格 | 搜索、历史、下载、收藏空态；不应为每个设置分组填满插画 |

## 3. 可直接查看的一手参考

### Phosphor：前景与底块

官方 SVG 资产按不同 weight 存放，可对比相同语义的形状处理；官方仓库明确说明 Duotone 的前/背景层实现。[Phosphor core](https://github.com/phosphor-icons/core)

- [官方 Duotone 浏览入口](https://phosphoricons.com/?size=64&weight=duotone)
- [官方 Play Duotone 资产页](https://github.com/phosphor-icons/core/blob/main/assets/duotone/play-duotone.svg)
- [官方 Star Four Duotone 资产页](https://github.com/phosphor-icons/core/blob/main/assets/duotone/star-four-duotone.svg)

Playra 建议：只借鉴主次层次与简洁造型。精选图可由一张圆角播放卡、大实心三角和一个较大的四角星构成；星是品牌装饰，不能代替“评分”的五角星语义。浅紫底块控制在少量局部，避免一圈圈细线和很多漂浮小点。

### Fluent 2：圆润但不繁复

官方图标规范强调语义可识别，并提醒不要通过附加标记引入过多复杂度；系统图标使用单色。形状规范将圆角与描边作为一致性属性，要求按元素尺寸考虑视觉重量，并使用圆润端点。[Iconography](https://fluent2.microsoft.design/iconography/)、[Shapes](https://fluent2.microsoft.design/shapes/)

Playra 建议：将这套一致性原则用于自绘图形，选一组固定圆角、圆端点与粗细比例。不要把微软产品图标、多色文件图标和系统操作图标混为同一素材类别；也不为本次装饰工作更换整站控件库。

### Material Symbols：小尺寸是独立设计问题

Google 指南说明 fill、weight、grade、optical size 的不同作用，optical size 覆盖 20–48 dp；SVG 可以从官方图标库取得。官方仓库说明 Rounded 是三类之一，且 Material Symbols 没有双色款。[官方指南](https://developers.google.com/fonts/docs/material_symbols)、[官方仓库](https://github.com/google/material-design-icons#material-symbols)

Playra 建议：24–28 大小的栏目符号按实际尺寸检查，降低细节数量并留出内部空隙；120 以上的空态另做构图，不能只是把小图放大后增加散点。SVG 中固定的路径不会因为放大/缩小自动获得字体的 optical-size 调整，需要手工校准。

### Carbon：空态图必须服从任务

官方规范将图形列为可选内容，要求关联当前状态；空间不足可以只显示文字。大面积同时出现多个空态时，重复插画可能降低效果。装饰图应被屏幕阅读器略过，重要信息应由正文表达。[Carbon Empty states](https://www.carbondesignsystem.com/building-blocks/core/patterns/empty-states)

Playra 建议：首访、无搜索结果、被条件筛空、真正失败分别表达。每张图后有简短标题与适当下一步；不通过“星星和笑脸”淡化失败，也不让空态比实际内容更复杂。

## 4. Playra 的具体图形语法

以下均为本项目建议值，需要页面实看后微调，不是官方设计系统规定：

- **形体**：每个小图一个主形体，最多一个语义附加符号；采用粗圆轮廓和圆端点。播放三角实心，四角星面积足够大，避免缩小后变成杂点。
- **颜色**：品牌浅紫主轮廓＋同色低透明底块；不依赖彩虹渐变、发光、复杂阴影表现精致。
- **栏目尺寸**：按 24–28 的实际显示尺寸设计并检查；相邻标题与图标垂直居中，图形不碰标题。
- **空态尺寸**：通常 120–160，仍保持简单块面；小高度或 1.6× 字体时优先保证文案和操作可见。
- **页头装饰**：使用相同粗圆块面图形，通过已有低透明方式呈现；减少细轨道、连接节点和随机散点；不覆盖标题、日期、海报或控件。
- **成熟感**：来自明确轮廓、稳定比例、恰当留白和一致重心；不用拟人表情、糖果渐变或大量玩具般零件。
- **接入注意**：本项目部分 `SvgPicture` 带 `ColorFilter`。前后层若通过同色不同 alpha 表达，需要验证整体着色后仍保留层级；不可只看独立 SVG 预览。

## 5. 可以追加的 SVG 与先后顺序

本表是资产设计建议，文件名为候选，不表示已经新增或接入。

| 优先级 | 位置 | 建议构图 | 使用限制 |
|---|---|---|---|
| P1 | 热播榜 | 简洁榜位/热度主体＋实心重点；与精选保持同一粗圆重量 | 标题图形不替代排名数字，避免与评分角标混同 |
| P1 | 精选推荐 | 圆角播放卡＋实心三角＋大四角星 | 作为整组风格标尺，星不应重复铺满背景 |
| P1 | 继续观看 | 圆角播放卡＋明确的回看/进度语义 | 进度装饰不能被误读为真实观看百分比 |
| P2 | 历史空态 `modern-history-empty.svg` | 胶片卡＋粗圆回看箭头 | 只在无记录时；正文引导去发现内容 |
| P2 | 下载空态 `modern-download-empty.svg` | 圆角离线收纳盒＋向下箭头 | 不在每条下载任务旁重复大图 |
| P2 | 图片搜索空态升级 | 圆角画面＋粗圆取景角，内部一块简单图像 | 不画多个复杂扫描环；上传操作始终最明显 |
| P2 | 规则空态 `modern-rules-empty.svg` | 两块大拼图/模块，少量插接关系 | 不用细线节点网络；编辑器表单不放同款背景 |
| P3 | 同步未连接 `modern-sync-empty.svg` | 两个圆角设备＋单一同步符号 | 只用于连接前的说明区，工作中用状态图标 |
| P3 | 讨论空态升级 | 一主一辅圆角对话框 | 小体量，少量底块；避免抢过详情内容 |

当前已安排的 ranking / curated / resume 与发现、日历、追番、我的相关重绘应先形成稳定的一组，再扩大资产数量。保持成熟感的关键是控制数量和语义重复，不是每页都增加一张图。

## 6. 不应该装饰的位置

- 视频画面、播放控制条、进度滑块、选集格子：保留内容与操作识别，使用标准功能图标。
- 解码器、渲染器、网络配置、WebDAV 表单、规则编辑/测试：改善排版和反馈比增加背景图更有价值。
- 删除确认、不可恢复操作、启动错误：需要明确文案和行动层级，不用四角星制造庆祝感。
- 帮助与隐私正文：使用阅读型宽度和段落结构，不插入无信息的 SVG。
- 同一屏连续多个空模块：优先合并状态或降低为文字提示，不重复放多张大型插画。

## 7. 核查与交付边界

已实际搜索并打开以上官方文档、官方仓库与资产页面；排除了第三方聚合站、个人博客和 Pinterest/Dribbble 风格转述作为事实依据。Phosphor 网站与 Google 图标目录依赖 JavaScript，核心事实由官方仓库和文档交叉确认；未宣称已在浏览器逐个渲染这些外部素材。

本研究只新建此 Markdown，不下载外部图片、不复制第三方 SVG 到项目、不增加库、不修改接口或运行时。最终 Playra SVG 的视觉效果、Flutter 渲染、可点击区域、读屏表现及 320/390/768/1440 与 1.6× 字体验证仍以主代理实际检查结果为准。
