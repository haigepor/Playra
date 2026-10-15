# Playra 全页面样式审查与 SVG 设计建议

> 后续实施更新：历史、下载、规则、同步及追加的线路、标签、奖杯和完整页头显示已落地；最新状态与验证见 [本轮实施记录](utility-pages-refinement-20261015.zh.md)。下文保留对应阶段的分析与历史证据。

日期：2026-10-15。代码基线：`37501c88`。审查对象为当前工作区的 Flutter 页面、路由、主题与 SVG 使用方式；工作区原有接口及其他用户改动保持原样。

本报告区分“源码确认的现状”“设计建议”“本轮轻量装饰实施范围”。源码审查不等于 Web、Android、iOS 已逐页运行验收。文中行号为审查时定位，后续编辑可能移动；实际运行检查结果见第 10 节。

## 1. 总体结论

新版已有一致的深蓝黑底色、淡蓝紫强调色和圆角卡片基础，适合继续完善。当前最明显的改善空间是页面宽度规则、信息层级、控件与图标一致性，以及空态对不同任务的表达。SVG 应加强栏目识别和必要状态表达，不能替代这些布局工作。

建议把图形分成四类：栏目符号、功能图标、空态插画、背景装饰。热播榜适合有辨识度的小型榜单符号；搜索、下载、历史可以有专属空态；播放器控制、密集设置与编辑表单应保持克制。

## 2. 本轮实施范围与未实施建议

本轮已完成以下轻量装饰设计及接入，素材与交互预览一并交付：

用户已提供明确视觉参考：整组图形以新 `curated` 图标为基准，采用粗圆描边、浅紫实心或低透明块面、实心播放三角与大四角星。页头仍通过原有低透明方式渲染，但素材本身减少细线轨道与连接节点，保持缩小后可辨认的形体。

| 范围 | 文件 / 内容 | 目的 |
|---|---|---|
| 新增栏目 SVG 3 个 | `assets/images/modern-section-ranking.svg`、`modern-section-curated.svg`、`modern-section-resume.svg` | 为热播榜、精选推荐、继续观看建立小尺寸语义符号 |
| 重绘已有 SVG 7 个 | `modern-discover-decoration.svg`、`modern-calendar-decoration.svg`、`modern-library-decoration.svg`、`modern-profile-decoration.svg`、`modern-profile-empty.svg`、`modern-search-empty.svg`、`modern-home-empty-feed.svg` | 让发现、日历、追番、我的及相关空态更符合页面内容 |
| 轻量接入 | 对应栏目标题与现有装饰位置 | 保持信息结构与主要交互，统一图形语气 |
| 扩展空态 6 个 | 新增 `modern-library-empty.svg`、`modern-download-empty.svg`、`modern-calendar-empty.svg`；重绘 `modern-image-search-empty.svg`、`modern-player-empty-source.svg`、`modern-player-empty-discussion.svg` | 前三个为待接入设计素材；后三个沿用现有引用位置 |
| 设计交付 | 本报告、`svg-style-references-20261015.zh.md`、`svg-style-preview.html` | 保存页面清单、官方参考、16 件 SVG 的交互预览与下载入口 |

页面宽度体系、播放器布局、全局控件、设置重组及新增三个空态的业务接入均为后续建议，本轮不能宣称已经完成。以下矩阵中的“改进建议”也不代表已经修改。

## 3. 主页面、详情与播放矩阵

| 页面 / 视图 | 当前样式与作用 | 改进建议 | SVG 适用边界 |
|---|---|---|---|
| 发现 `/tab/popular/` | 分类导航、推荐、榜单、海报内容区、继续观看；内容宽 760 | 强化推荐/热度/续看的层级；栏目间距与标题基线一致；宽屏形成明确内容网格 | 热播榜、精选、续看用不同栏目符号；页头装饰低对比，不覆盖海报 |
| 发现内分类、分类浏览和榜单 | 复用发现内容区域，不是另一套主导航 | 分类选中、数量/排序、进入全部内容的操作保持一致 | 复用栏目符号，不给每个题材造一套装饰 |
| 日历 `/tab/timeline/` | 日期/星期切换、放送列表、季度与追番筛选；宽 760 | 今日、选中日期、放送状态形成清楚层级；长名称与多状态避免争抢空间 | 日历刻度或日程符号；背景图不要像可点击日期 |
| 追番 `/tab/collect/` | 状态标签、搜索排序、卡片/列表、同步；宽 1200 | 明确状态标签与内容计数；列表和网格使用同一信息优先级；统一筛选控件 | 收藏/书架语义图；只在页头和空态出现 |
| 我的 `/tab/my/` | 观看统计、快捷入口、分组菜单、同步状态；宽 760 | 突出观看记录与继续使用入口；统计数字不抢设置入口；连接状态有文字解释 | 个人观看空间图形；空态更轻，不制造虚假的统计图 |
| 番剧详情与播放 `/info/`、`/video/` 的番剧分支 | 视频、资料/讨论/评价、来源、选集；复用原播放布局 | 播放操作优先，统一来源/选集/资料的节奏；宽屏与 SDK 播放页分别验收 | 只在资料空态或来源空态使用图；视频与控制条不用背景装饰 |
| SDK 影视详情与播放 `/info/` 的另一参数分支 | 视频、来源线路、资料、选集；外层宽 900 | 明确线路和选集层级；与番剧播放统一控件视觉；宽屏策略需单独设计 | 复用播放器语义图，不创建第二套品牌语言 |
| MioMedia 详情 | 复用 SDK 详情实现 | 随 SDK 页面验收，避免重复算作独立设计系统 | 无需单独 SVG |
| `ContentWorkPage` | 有实现文件，未确认用户可达入口 | 不能仅凭文件存在算作现用页面；接入前再审查 | 暂不为其新增资产 |

主要证据：`lib/presentation/modern/home/modern_home_view.dart:60-64`、`calendar/modern_calendar_view.dart:99-103`、`library/modern_library_view.dart:132-136`、`profile/modern_profile_view.dart:33`（以上后三项相对于 `lib/presentation/modern/`）；`lib/presentation/modern/pages/sdk_player_detail_page.dart:1161`。番剧播放复用 `lib/pages/video/playback_scaffold.dart:379` 的 `VideoPageLayout`，其填满窗口/侧栏策略见 `lib/pages/video/video_page_layout.dart:28`，不能用 SDK 的 900 宽布局推断另一播放器。

## 4. 搜索、资料、历史与下载

| 页面 / 入口 | 当前样式 | 改进建议 | SVG 建议 |
|---|---|---|---|
| 聚合搜索 `/search/` | 搜索框、类型 Tab、地区筛选、结果列表、来源进度；宽 760 | 输入—筛选—结果数层级固定；来源进度为辅助信息；初始与无结果状态区分 | 初始态用海报与放大镜；结果列表不铺装饰 |
| 番剧资料搜索 `/search/metadata` | 64 高搜索栏、历史、条件入口、海报网格；宽 960 | 与聚合搜索统一输入/筛选结构和边距；保留不同结果组织方式 | 复用搜索图；筛选保留标准线性图标 |
| 标签搜索 `/search/:tag` | 复用番剧资料搜索 | 当前标签放入可移除条件区域 | 不另增 SVG |
| 图片搜索 `/search/image` | 文件/链接切换、上传预览、识别结果；宽屏双区 | 上传区域成为明确主操作；相似度、集数、时间点层级清楚；更换图片为次操作 | 扫描取景框与画面插画；沿用原空态位置 |
| 人物资料弹层 | 资料/吐槽 Tab、人物信息与评论 | 人物名、头像、字段层级一致；评论空态更轻 | 无评论可用小对话框图，资料不加背景 |
| 图片预览 `/image-preview` | 全屏图片、关闭/切换按钮、失败状态 | 统一按钮命中区、键盘焦点、切换反馈 | 不需要装饰 SVG |
| 历史 `/settings/history/` | 搜索、来源筛选、按时间分组、编辑删除 | 统一旧圆角与图标；突出最近观看和进度；长标题不挤压操作 | 后续可补粗圆胶片与回看符号空态 |
| 下载 `/settings/download/` | 作品折叠卡、总/分集进度、暂停继续重试删除 | 区分下载中/完成/失败；数值与状态比技术细节突出；统一操作位置 | 后续可补离线收纳空态，任务状态沿用标准图标 |

证据：`lib/presentation/modern/pages/content_search_screen.dart:115-117`；`lib/pages/search/modern_search_widgets.dart:5-14`；`lib/pages/search/image_search_page.dart:320-405`；`lib/pages/info/character_page.dart:101-140`；`lib/bean/widget/image_preview.dart:27`；`lib/pages/history/history_list_view.dart:80-102`；`lib/pages/download/download_page.dart:50-66`。

## 5. 全部设置与管理页面

设置页共用 `SettingsAppearanceHost` / `ModernSettingsScope`，不代表内部布局已经完全统一。路由依据：`lib/pages/settings/settings_module.dart:28` 起，及 plugin、proxy、danmaku、about 子模块。

| 页面 / 设置下路由 | 当前样式 | 改进建议 | SVG 边界 |
|---|---|---|---|
| 设置首页 `/settings/` | 播放/资源/应用/其他分组；宽屏 280 左栏 | 建立统一栏宽、内容宽度和边界；说明文字保持可读 | 分类图标统一线宽，不逐组加插画 |
| 播放 `/player` | 解码、行为、诊断、参数、恢复默认 | 常用优先，诊断可折叠，参数值对齐，恢复操作分离 | 最多标题小播放符号 |
| 解码器 `/player/decoder` | 单选列表与兼容说明 | 当前/推荐项区分；长说明独立显示 | 无需 SVG |
| 渲染器 `/player/renderer` | 单选列表 | 与解码器布局一致 | 无需 SVG |
| 超分 `/player/super` | 前置条件、模式选择、默认行为 | 前置条件为中性提示；模式用简短效果说明 | 不加装饰 SVG |
| 弹幕 `/danmaku` | 来源、屏蔽、显示、样式多组滑块开关 | 将字号/透明度/区域集中；设置预览比插画更有价值 | 可用表达实际设置的弹幕示意，不用静态花纹 |
| 屏蔽 `/danmaku/shield` | 输入添加、规则列表；宽 1000 | 关键词/正则明确区分；就地提示；统一输入框 | 空态小对话框与盾牌即可 |
| 操作 `/keyboard` | 快捷键、键帽、恢复；宽 1000 | 功能名与键帽对齐；监听状态明显；触屏说明适用范围 | 键帽本身就是视觉语言 |
| 外观 `/theme` | 新版配色说明、字体、平台选项 | 给字体与品牌配色小预览；说明不抢主视觉 | 品牌标记可复用 |
| 屏幕帧率 `/theme/display` | Android 模式单选 | 系统当前值、选中值、自动模式区分 | 无需 SVG |
| 界面 `/interface` | 新旧版、启动页、追番布局、评分、窗口行为 | 版本/布局用微型示意帮助选择 | 可做真实布局缩略示意，非背景插画 |
| 同步 `/sync` | Bangumi/WebDAV 卡片与连接状态 | 两服务的未连接/已连接/处理中表达一致 | 小设备连线符号即可 |
| Bangumi `/bangumi/` | 账号、Token、自动同步、冲突偏好 | 按连接—同步—冲突策略组织；结果就地显示 | 标准书签/同步图标 |
| WebDAV `/webdav/` | 服务器、启用、同步内容 | 与 Bangumi 统一反馈位置和操作层级 | 标准设备/云图标 |
| WebDAV 编辑 `/webdav/editor` | 连接表单 | 连接测试、保存反馈明确；表单宽度宜小于网格 | 无需装饰 SVG |
| 网络 `/proxy` | 访问加速与代理，Web 有平台说明 | 平台能力说明为信息态；不同方式选中态一致 | 小连接符号即可 |
| 代理编辑 `/proxy/editor` | 原生表单，Web 为不适用说明 | Web 正常能力说明不使用失败式视觉；原生验证就地反馈 | 无需装饰 SVG |
| 规则管理 `/plugin/` | 介绍、筛选、多选、规则卡、批量操作；宽 1000 | 压缩介绍，分类/启用/更新状态清楚；减少操作竞争 | 小拼图节点符号；空态可放大 |
| 规则仓库 `/plugin/shop` | 可安装规则与状态；宽 1000 | 已安装/可更新/可安装统一标签和操作区 | 复用规则图 |
| 规则编辑 `/plugin/editor` | 基本/搜索/章节/高级四段表单，底部动作；宽 900 | 当前段、未保存、错误就地可见；示例统一 | 无需装饰 SVG |
| 规则测试 `/plugin/test` | 输入、搜索请求/结果解析/播放线路三步；宽 900 | 三步状态统一；输出区域使用等宽字体和复制入口 | 功能状态图标即可 |
| 下载设置 `/download-settings` | 并发滑块、路径、缓存、说明 | 数值块一致，长路径换行，说明靠近相关控件 | 无需 SVG |
| 存储 `/storage` | 用量/清除、开发诊断 | 清除前后用量可见；图表只呈现有依据的数据 | 小存储图标即可 |
| 更新 `/update` | 应用/规则检查开关 | 沿用统一开关列表 | 无需 SVG |
| 关于 `/about/` | 品牌卡、orbit SVG、帮助/隐私 | 品牌标记一致，装饰低于文字，版本为辅助信息 | 适合品牌 orbit |
| 帮助 `/about/help` | 正文 | 按用户动作分段，标题可扫描 | 无需 SVG |
| 隐私 `/about/privacy` | 正文 | 窄阅读宽度与清晰行距 | 无需 SVG |

组件证据：`lib/bean/settings/settings_list.dart:23-25,55-57,172-243,310-320,424-428`；`lib/pages/settings/settings_page.dart:224-244`；`lib/presentation/modern/settings/modern_settings_scope.dart:77-101,147-197`。规则模块见 `lib/pages/plugin_editor/plugin_module.dart:10-48`，弹幕见 `lib/pages/settings/danmaku/danmaku_module.dart:5-13`，代理见 `lib/pages/settings/proxy/proxy_module.dart:5-10`，产品信息见 `lib/pages/about/about_module.dart:6-35`。

## 6. 引导、异常、弹层与兼容入口

| 类型 | 当前覆盖 | 设计建议 |
|---|---|---|
| 初始化 `/` | 品牌和准备状态 | 与正式品牌一致，不加无意义进度 |
| 引导 `/onboarding` | 使用约定、仅 Android 的更新来源、访问加速 | 步骤节奏一致，小屏控制顶部插画高度；同构小图表达不同步骤 |
| 初始化失败 `/error` | 标题、说明、操作、可选细节 | 一项明确下一步；细节折叠；与空结果区分 |
| 路由参数错误 | `RouteErrorPage`，按场景继承设置或二级主题 | 返回动作与信息层级一致 |
| 存储初始化失败 | `StorageErrorPage`；新版已包二级主题 | 使用同一异常体系，不误判为完全未接入新版 |
| 搜索弹层 | 筛选：题材、时间、评分排名、收藏状态；搜图提示 | 固定标题/底部动作，长内容内部滚动；不放大插画 |
| 人物与播放相关弹层 | 人物资料、来源线路、选集、资料、评分/评价、截图、同步播放 | 区分阅读与选择任务；按钮、关闭、标题节奏一致 |
| 弹幕弹层 | 设置、屏蔽、时间校准 | 与设置页共用控件与数值格式；状态和设置结果可识别 |
| 下载弹层 | 下载选集、删除单项/全部、失败提示 | 选中数量与下载动作清楚；删除保持明确文字 |
| 规则弹层 | 添加、导入、分享、删除、来源分类 | 表单就地反馈；复制/导入/删除的动作语义清楚 |
| 其他对话框 | 低内存模式、追番同步、历史清空、播放/弹幕恢复默认、缓存清除 | 控制信息密度；危险动作不使用装饰性强调 |
| 兼容入口 | `/settings/about/license`、`/settings/about/legal`、`/settings/about/credits` | 当前均返回关于页，不重复计算成三套内容页 |
| 开发入口 | `/settings/storage/logs`、`/ui/components` | 仅开发工具开关开放，独立于普通用户主流程 |

`plugin_shop_step.dart` 虽然存在，当前引导步骤没有调用它。证据：`lib/pages/onboarding/onboarding_page.dart:36-52,74-83`。引导图形为 `onboarding_step_layout.dart:34-43`；错误图形为 `lib/presentation/modern/secondary/secondary_theme.dart:198-202`；存储错误新版主题见 `lib/pages/error/storage_error_page.dart:20`。开发入口见 `lib/pages/index_module.dart` 与 `lib/pages/settings/settings_module.dart` 中的 `AppBuildPolicy.developerTools` 分支。

## 7. 优先级与跨页面一致性问题

| 优先级 | 发现与影响 | 建议 | 证据 |
|---|---|---|---|
| High | 760/900/960/1000/1200 等内容宽度并存，设置又有固定左栏；切页密度改变明显 | 建立阅读、表单、媒体网格三种明确宽度规则；不要简单强制所有页面一个宽度 | 主页面见第 3 节；`settings_list.dart:23-25`；`history_list_view.dart:99-102`；`plugin_editor_page.dart:457-459` |
| High | 页头 `ModernPageArt` 位于内容约束外并靠窗口右侧，宽屏可能与正文脱离 | 后续让装饰跟随内容容器定位；先用真实 1440 宽截图判断，不仅看 SVG 文件 | `modern_page_art.dart:14-34`；`modern_home_view.dart:60-64`；日历/追番同结构 |
| High | 栏目符号、评分、排名承担不同含义；当前排名与评分复用金色角标，语义容易混同 | 榜位使用数字/排名符号，评分保持星形与小数；颜色不能是唯一差异；先做热播榜标题标记 | `lib/presentation/modern/miomedia/miomedia_browse.dart:274-295`；`lib/presentation/modern/widgets/modern_anime_cover.dart:42-68` |
| High | 两种播放器宽屏策略不同 | 分别确认全屏、横屏、侧栏和选集，不以一个通过代表另一个 | `playback_scaffold.dart:379`；`video_page_layout.dart:28`；`sdk_player_detail_page.dart:1161` |
| Medium | SVG 统一着色会抹平多色设计；素材内部透明度还会叠加 | 小栏目符号、空态、背景分别定义颜色与透明度；按实际 Flutter 组件渲染检查 | `secondary_theme.dart:26-39`；`modern_page_art.dart:26-29` |
| Medium | 历史搜索圆角 28、分组 24/4、规则输入 16、公共现代输入 12，形状语气不一 | 优先统一同类控件，保留有任务依据的差异 | `history_list_view.dart:80-82,224-226`；`rule_management_widgets.dart:159-169`；`modern_settings_scope.dart:147-164` |
| Medium | 部分现代页仍用旧 Material 图标，其他位置是 Lucide；同步图章仍是四瓣形 | 先统一线宽、尺寸和视觉重量；通用返回/搜索/播放不必手工重画 | `modern_settings_scope.dart:215` 起；`state_presentation.dart:22-39` |
| Medium | 历史/下载/规则等通用空态只是 132×86 容器里放一个 48 大小图标 | 后续补高复用语义插画，并区分未开始、空结果、被过滤、失败 | `lib/bean/widget/empty_state_widget.dart:31-48` |
| Medium | Web 代理编辑的不适用说明使用失败视图 | 改中性信息卡，正常能力边界不呈现为异常 | `proxy_editor_page.dart:115-123`；`secondary_theme.dart:198-202` |
| Medium | 设置正文 14、辅助 12、最小标签 11，密集界面需设备验证 | 保留 48 触控区，优先提高信息层级和换行能力，避免只缩小字号 | `modern_settings_scope.dart:77-96`；`settings_list.dart:310-320,424-428` |

以上短文件名分别位于已列出的 `lib/presentation/modern/`、`lib/pages/` 和 `lib/bean/` 对应目录。定位的是审查时实现；本轮轻量接入可能使行号移动。

## 8. SVG 统一设计规范

- **整组视觉基准**：遵循用户选定的 `curated` 图形风格：粗圆描边、浅紫块面、实心播放三角、大四角星；不同页面通过轮廓与内容语义区分，避免重新回到细线日历与连接节点的图形语言。
- **栏目符号**：目标视觉尺寸约 24–28，使用清楚的粗圆轮廓与块面；热播榜表达排名/热度，精选突出播放卡与四角星，继续观看突出播放与进度。不能仅在现有竖条旁堆一个无关图。
- **功能图标**：统一 18–22 左右的视觉尺寸与笔画重量；命中区域仍按控件要求保留。返回、关闭、播放、暂停等优先复用现有成熟图标。
- **空态插画**：通常 120–160，沿用同一粗圆与块面风格；标题与下一步仍是主要信息。在小高度/大字体时收缩或隐藏纯装饰，不能挡住操作。
- **背景装饰**：素材采用简洁块面，沿用页头原有低透明渲染；减少细线轨道和连接节点。可读性低于内容，不能制造可点击错觉，不覆盖标题、日期、海报和控制条。保持 `IgnorePointer` 与 `ExcludeSemantics`。
- **颜色**：以浅紫实心/低透明填充和品牌蓝紫描边为主；状态色仅用于有明确语义的位置。通过文字、形状和图标共同表达状态，不把金色扩散到所有页面。
- **兼容性**：优先基本 path/rect/circle/group；复杂滤镜、外部字体、脚本和外链不应成为资产依赖。多色资产必须检查是否被宿主 `ColorFilter` 覆盖。
- **留白**：统一 viewBox 安全边界，按 1× 实际显示尺寸验收；同样 24 宽不代表视觉重量相同。
- **动画**：静态优先。若后续增加动效，必须尊重减少动画设置，且不能干扰阅读和播放。

## 9. Web / Android / iOS 验证边界

三端共用 Flutter 新版页面，平台功能、系统返回、安全区和窗口形态存在差异。Web 验证不能直接证明 Android/iOS 真机可用；桌面浏览器模拟窄宽度也不等于真机验收。

| 尺寸 / 条件 | 验证重点 | 代表页面 |
|---|---|---|
| 320 宽 | 标题/图标不挤压；按钮不溢出；弹层底部动作可达；海报网格合理降列 | 发现、搜索、追番、设置、规则编辑、所有选择弹层 |
| 390 宽 | 手机常规比例；页头与首屏密度；SVG实际大小；长标题 | 四主页面、搜索、图片搜索、历史、下载 |
| 768 宽 | 设置双栏转换；侧栏与详情可用宽度；图片搜索双区；横屏布局 | 设置及表单、图片搜索、两种播放器 |
| 1440 宽 | 装饰与正文对齐；内容最大宽度；栏位密度；鼠标悬停/键盘焦点 | 四主页面、搜索网格、规则列表、两种播放器 |
| 1.6× 字体 | 标题换行、参数值、筛选 chips、Tab、键帽、底部操作；必要时装饰让位 | 设置、搜索、规则、历史、引导、弹层 |
| Web | Hover/focus、Tab/Enter/Escape、缩放、窗口 resize、滚动与弹层关闭 | 全流程重点页 |
| Android | 系统返回、状态栏/导航栏、安全区、横竖屏、48 触控区、大字体 | 主导航、播放器、设置和弹层 |
| iOS | 顶部/底部安全区、返回手势、键盘遮挡、动态字体、横竖屏 | 主导航、搜索表单、播放器、弹层 |

每类至少覆盖正常、加载、空结果、已有内容、长标题；交互页另测选中/禁用/处理中/可重试。装饰图必须不增加读屏噪声、不拦截点击、不导致内容高度抖动。评分开关关闭后，排名语义仍应清楚。

## 10. 第一阶段 SVG 验证状态、影响与后续

- **DONE — 源码审查与官方参考**：已核对上述页面与组件；官方图形参考见 [SVG 风格研究](svg-style-references-20261015.zh.md)。
- **DONE — 16 件图形设计**：6 件新 SVG、10 件已有 SVG 重绘。3 件新空态保留为设计素材；其余图形已接入或沿用原引用。未修改业务、接口、控制器或平台配置。
- **DONE — 静态完整性**：16 件 SVG 严格 UTF-8 与 XML 解析通过，无 BOM、替换字符、外部图片、脚本或滤镜依赖；本轮 Dart/HTML/文档 UTF-8 检查通过。相关差异的 `git diff --check` 通过。
- **DONE — Flutter 静态检查**：`flutter analyze --no-pub` 针对本轮四个 Dart 文件通过，输出 `No issues found`。
- **DONE — 相关回归**：六个既有测试文件共 59 项通过；扩展素材加入后，播放器素材与二级页面两文件共 22 项通过；最终修正三张后景填充后，播放器素材渲染测试再次通过。重叠用例不累加为独立数量。
- **DONE — Web 构建**：最终 `flutter build web --no-pub --no-wasm-dry-run` 成功。沿用当前 8931 服务，没有重启或调整接口服务。
- **DONE — 设计预览运行检查**：[预览页](http://127.0.0.1:8931/design-review/index.html) 全部 16 件 SVG 加载成功，深浅背景、分类筛选与原色开关正常。320、390、768、1440 宽检查无横向溢出，预览页无控制台错误/警告。文件下载入口指向本地 SVG。
- **DONE — 应用实看**：390 宽发现页截图确认暖金热播榜图标与新的页头播放卡已渲染。截图：`.dart_tool/svg-app-discover-390.png`。浏览器缓存的旧页面需刷新；核查使用 `/?svg-review=20261015#/tab/popular/` 取得当前构建。
- **NEXT — 真机验收**：未运行 Android/iOS 真机；浏览器窄屏与 widget tests 不替代系统安全区、返回手势或播放器真机测试。完整页面矩阵为源码审查，不代表每个页面均经过运行验收。
- **NEXT — 设计后续**：可继续补观看历史、规则管理、同步未连接图形；页面本身优先统一宽度、输入控件与播放器宽屏策略。图形数量应服从真实状态需要。

应用运行仍有用户已说明正在修改的接口/封面 502，本轮未处理。这不影响独立 SVG 设计预览，也不能因此宣称应用所有请求均正常。

## 11. 文件清单与回退范围

所有 SVG 位于 `assets/images/`：

- 新增 6 件：`modern-section-ranking.svg`、`modern-section-curated.svg`、`modern-section-resume.svg`、`modern-library-empty.svg`、`modern-download-empty.svg`、`modern-calendar-empty.svg`。
- 重绘 10 件：`modern-discover-decoration.svg`、`modern-calendar-decoration.svg`、`modern-library-decoration.svg`、`modern-profile-decoration.svg`、`modern-profile-empty.svg`、`modern-search-empty.svg`、`modern-home-empty-feed.svg`、`modern-image-search-empty.svg`、`modern-player-empty-source.svg`、`modern-player-empty-discussion.svg`。
- 新增 `lib/presentation/modern/widgets/modern_section_mark.dart`，集中选择三种栏目资产并排除重复读屏语义。
- 修改 `lib/presentation/modern/home/modern_home_view.dart`、`lib/presentation/modern/miomedia/miomedia_browse.dart`、`lib/presentation/modern/miomedia/miomedia_rank_view.dart`，仅替换/添加栏目标题的 SVG 标记。
- 新增本报告、`docs/design/svg-style-references-20261015.zh.md` 和 `docs/design/svg-style-preview.html`。HTML 可在本地打开，使用相对路径读取源 SVG；8931 预览为 `build/web/design-review/index.html` 的生成副本，重新清理构建目录会移除副本，源文件保留。

原有 10 件 SVG 与三个被改动 Dart 文件的备份位于 `.dart_tool/svg-design-backup-20261015/` 对应相对路径。回退只应用这些文件的本轮差异；若其他任务随后编辑同文件，应按差异回退，避免整文件覆盖。新增文件可以单独移除。工作区存在并发接口、播放与规则变更，不能使用整体重置回退。

## 12. 后续材质、搜索与奖杯更新（2026-10-15）

### 已完成的交付

- 四张同材质透明背景：影院片单、放送日历、追番收藏夹、我的票根册，均为2172×724 RGBA。分别在发现/搜索、日历、追番、我的有足迹卡片接入；宿主控制透明度、最大宽度、裁切与淡出，并排除点击和重复读屏。
- 搜索页：900最大内容宽度，独立搜索按钮，48最小触控区，频道胶囊筛选；结果卡按海报、标题、年份类型、候选来源/作品资料分层。两枚18px SVG已接入；纸角SVG仍是设计候选。
- 播放页来源区：来源与线路分组，来源按钮为主、线路为辅；沿用真实数据和原操作。
- 七天热播榜前三名：用户最终选择生成式金/银/铜奖杯。三图同杯型、光线与纸质纹理，仅改变颜色和数字；32×36显示，96px解码宽度，海报左上内缩4px。原盾牌SVG保留为备选。
- 全页面细节分析见 [素材与页面映射](material-art-page-map-20261015.zh.md) 和 [二级页面细节](secondary-detail-design-20261015.zh.md)。历史、下载、规则、同步优先优化信息层级、状态和表单宽度；未把这些建议写成已实施。

### 本次验证证据

- **DONE**：8个相关视觉Dart文件 `flutter analyze --no-pub` 通过，`No issues found`。最终 `flutter build web --no-pub --no-wasm-dry-run` 成功（72.7s）。
- **DONE**：7张PNG确认RGBA且角落alpha=0；新增/修改文本严格UTF-8、无BOM和替换字符检查通过；目标路径 `git diff --check` 无空白错误。
- **DONE**：[细节预览](http://127.0.0.1:8931/design-review/ui-refinement-preview.html#ranks) 的14个图片引用均加载成功；320、390、1440宽无横向溢出；三枚实际尺寸均为32×36；此预览页控制台0错误/0警告。截图 `.dart_tool/trophy-preview-{320,390,1440}.png`。
- **DONE**：390宽实际搜索初始态截图 `.dart_tool/material-app-search-final-390.png`；搜索输入、筛选和结果卡逻辑作源码审查。未宣称完成搜索结果/播放换源的完整运行交互验收。
- **BLOCKED**：本轮既有Flutter测试在测试执行前被 `media_kit -> native_toolchain_c -> VisualStudioResolver.parseVswhere` 的JSON控制字符编码错误阻断：`FormatException: Control character in string (line 16, character 162)`。第10节59项通过属于前一阶段，不能作为本次改动的测试通过证明。
- **BLOCKED**：应用仍有用户已说明的接口/封面502及404；未修改接口。热播榜真实数据状态、各页面完整交互与Android/iOS真机没有全部验收。独立预览检查不替代真实产品验收。

### 主要文件、影响与回退

| 文件 | 目的与影响 | 回退来源 |
|---|---|---|
| `assets/images/modern-*-header-art.png`、`widgets/modern_page_art.dart` | 四张背景与共用页头布局；只影响视觉和图像解码 | `.dart_tool/header-art-refinement-backup-20261015/`；新增PNG可按引用移除 |
| `home/modern_home_view.dart`、`calendar/modern_calendar_view.dart`、`library/modern_library_view.dart`、`profile/modern_profile_view.dart` | 内容栏对齐与背景宿主 | `.dart_tool/header-art-refinement-backup-20261015/`、`.dart_tool/material-series-backup-20261015/` |
| `pages/content_search_screen.dart`、两枚搜索SVG | 搜索页层级、密度与来源说明 | `.dart_tool/search-redesign-backup-20261015/` |
| `pages/modern_player_detail_page.dart` | 来源/线路操作的视觉分组 | `.dart_tool/source-style-backup-20261015/` |
| `miomedia/miomedia_browse.dart`、三枚 `modern-rank-trophy-*.png` | 前三名奖杯，沿用名次语义与点击 | `.dart_tool/trophy-rank-backup-20261015/`；更早角标版本见 `.dart_tool/rank-badge-backup-20261015/` |
| `docs/design/ui-refinement-preview.html`、三份生成提示词记录 | 可审阅预览及原始提示词 | 预览修改前副本在奖杯备份目录；新增文档独立移除 |

表中Dart路径均相对 `lib/presentation/modern/`。回退应只逆转本次视觉差异，不能整文件覆盖并发业务改动。三枚原始透明奖杯PNG共约4.55MiB；应用已限制解码尺寸，网络传输体积仍可后续以独立压缩流程优化。

原始背景提示词正文完整保存在 [cinema-header-imagegen-prompt.md](cinema-header-imagegen-prompt.md)，三张页面变化在 [material-series-imagegen-prompts.md](material-series-imagegen-prompts.md)，奖杯母版与银/铜派生在 [rank-trophy-imagegen-prompts.md](rank-trophy-imagegen-prompts.md)。均使用内置image_gen；未使用CLI/API fallback。
