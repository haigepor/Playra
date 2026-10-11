# 播放与详情一体页交付记录

日期：2026-10-11；仓库：D:\project\Playra；代码基线：acdcbab8。当前交付为 PARTIAL，原生媒体验收受设备和来源条件限制。

## 已实现

- 采用用户确认的紧凑影音方向，播放器与详情/讨论/评价标签固定，内容独立滚动；减少分区卡片边框，选集与主要操作靠近。
- `/info/` 接收真实 BangumiItem；`/video/` 保留在线/离线参数。新版使用共享 PlaybackScaffold，旧 InfoPage 与 VideoPage 包装保留。资料态不构造假的在线播放参数。
- SourceSheet 的可选回调允许原位播放；换源先停止旧媒体、取消旧异步会话，再安装新上下文。未知目标明确选集并从头播放。续播验证同作品、站点、详情地址及唯一剧集地址，拒绝套用旧列表索引。
- 全部选集使用原始身份、50 集分段、惰性网格、升降序、线路浏览与当前集定位。完成下载的剧集显示真实标记；只有实际 playing 且身份一致时显示播放标记。
- 资料弹层提供简介、角色、关联与制作人员；相关作品跳转前暂停原媒体。讨论映射真实 Bangumi 分集 ID，未知 OVA/SP 不猜正片编号，并提供手动匹配。整部评价保留登录要求、分页、重试、十分制与隐藏评分。
- 全屏视图卸载与控制器销毁分开，支持同一路由切换新旧呈现后重新进入全屏。播放页局部主题保持至少 48 dp 的按钮区域。
- 六张 SVG 逐项审查，五张重设计，静态播放标记保留。完成独立素材和完整交互 HTML 预览；示例数据明确标识为设计演示。
- 后续用户追加：发现页顶部改用与追番页相同的原生 TabBar、3 dp 圆角短线、文字宽度指示器及 14 dp 字号。横向滑动浏览分类，点击后切换；动漫子分类逻辑保留。

## 验证证据

| 检查 | 结果及边界 |
| --- | --- |
| 六个 SVG | 严格 UTF-8/XML 与禁止元素检查；通过项目安装的 flutter_svg 实际尺寸渲染测试。 |
| 重点契约回归 | 61 项通过：身份、异步会话、来源服务、新旧导航、移动 Tab、素材、选集和全屏卸载/返回。 |
| 发现页 | 7 项通过：原生指示器、滑动不误切换、末尾分类可达、子分类同步，以及 320/390/844 宽度和放大字体布局。 |
| Flutter analyze | 无 error/warning；32 条 info，位于既有代码或既有写法，不纳入此次无关清理。 |
| Web | 构建入口 lib/main_home_preview.dart，输出 build/modern-player-preview。实际页面预览端口 8938。 |
| Android | tool/build-android.ps1 可构建 debug APK。未连接真机/模拟器，因此构建成功不代表原生运行验收。 |
| HTML 预览 | 320 宽、2 倍字体选集弹层无横向溢出，按钮至少 48 px；Escape 关闭并恢复触发按钮焦点；评分隐藏后不占位。 |
| 实际 Web 页面 | 真实首页卡片进入一体页；未选源展示真实资料和选择来源入口。切讨论显示“先选择播放剧集”，评价 API 失败显示明确重试状态。来源未配置提示真实原因，取消可回原页面。 |

发现页旧测试文件完整运行有三项失败：`category rails scroll independently and expose more and corner metadata`、`search, calendar, details and resume preserve callbacks and identity`、`feed selection loads new subjects and retry recovers an empty response`。使用 HEAD 的原页面和原测试在独立临时目录复跑，这三项同样失败；旧测试所用卡片 key/空状态约定已过期。本次仅更新顶部 Tab 对应测试，不以修改无关测试掩盖基线问题。

浏览器请求 Bangumi 资料、评价及部分图片代理出现 HTTP 502；推荐数据镜像仍返回真实作品。当前 Web 来源配置为空，没有实际初始化媒体。未选源、讨论和失败状态截图不能充当真实播放证据。

## 预览与截图

- 实际应用：http://127.0.0.1:8938/ ，从发现卡片进入新版一体页。
- 第二稿设计：http://127.0.0.1:8937/docs/design/modern-player-preview.html 。
- 素材审查：http://127.0.0.1:8937/docs/design/modern-player-assets.html 。
- 设计截图：`docs/design/modern-player-preview.png`、`modern-player-preview-narrow.png`、`modern-player-assets.png`。
- 实际页面截图：`docs/design/modern-player-runtime-detail.png`、`modern-player-runtime-narrow.png`、`modern-player-runtime-info.png`、`modern-player-runtime-source.png`。
- 发现/追番对照：`docs/verification/discovery-tabs-library-aligned.png`、`discovery-tabs-narrow.png`、`library-tabs-reference.png`。发现页使用原生 tab 语义；点击动漫可展开真实子分类。
- 最新实际页面所有可见主要按钮，浏览器语义边界均为至少 48 px；320 宽仍保留简介、追番、下载、选源与返回。来源弹层由关闭按钮取消后仍回同一详情页。
- 来源弹层当前沿用旧版键盘行为，Web 的 Escape 未关闭该弹层；应使用关闭按钮。HTML 演示中的 Escape 验证不覆盖这个旧版弹层。

## 文件范围与影响

| 文件/目录 | 目的与影响 |
| --- | --- |
| assets/images/modern-player-*.svg | 播放相关占位/空状态/可选装饰；未改全局资源声明或依赖。 |
| lib/pages/video/video_page.dart、playback_scaffold.dart | 原播放外壳提取与旧版兼容包装，影响共享媒体生命周期。 |
| lib/pages/video/video_controller.dart、playback_identity.dart、video_fullscreen_controller.dart | 原位换源、保守续播、异步取消及视图重新挂载。 |
| lib/pages/info/info_module.dart、lib/pages/video/video_module.dart | 路由作用域提供控制器并选择新旧页面，参数契约不变。 |
| lib/pages/info/source_sheet.dart、source_sheet_view.dart | 可选结果回调/空状态插画，旧调用保持原有导航行为。 |
| lib/presentation/modern/pages/modern_player_detail_page.dart、lib/presentation/modern/player/ | 新版结构与独立内容，复用实际业务能力。 |
| lib/pages/info/info_comments_view.dart、lib/bean/card/comments_card.dart | 可选非嵌套滚动、头部、隐藏/十分制评分；旧调用默认行为保留。 |
| lib/pages/player/episode_comments_view.dart、lib/bean/widget/empty_state_widget.dart | 可选空状态 Widget，默认保持旧版。 |
| lib/request/apis/bangumi_api.dart | 分集查询可选抛错，区分真正空数据与请求失败；默认兼容旧调用。 |
| lib/presentation/modern/home/modern_home_view.dart | 仅顶部主分类替换为与追番相同的 TabBar，未改推荐算法或根导航。 |
| test/modern_player_*_test.dart、test/modern_home_view_test.dart | 保护身份、渲染、选集、全屏重挂载、触控区域和新 Tab 行为。 |
| docs/design/modern-player-*、本文件及发现/追番对照 PNG | 设计、审查、截图和验收边界。 |
| openspec/changes/modern-player-detail/ | 用户已确认的独立变更契约与任务，原生未验项保留未完成。 |

开始时工作区干净；本任务未修改其他 OpenSpec 变更、pubspec/lock、根导航动画或控制面文件。测试自动更新的旧首页截图已恢复，避免混入无关图像变化。

## 剩余验收与回退

- BLOCKED：合法可用来源的真实选源/验证码/取消、快速切集、换源、续播、弹层与标签不断播，及离线文件成功/缺失流程。
- BLOCKED：Android 安全区、横竖屏、全屏返回、PiP、后台/音频焦点、键盘编辑和新旧界面切换的实机检查。当前没有设备或模拟器。
- DONE：代码、设计与局部契约验证；保持 OpenSpec 活跃，不能宣称原生媒体已全部验收。
- 回退位置是上述文件在 `acdcbab8` 的内容，以及新增文件清单。已有文件只按本任务 diff 逐项恢复；新增文件只删除本任务创建的准确路径。后续有其他修改时先保存差异，禁止整个仓库 reset --hard 或清理未追踪文件。
- 运行时可切回旧界面；此操作只改变呈现，不等同于代码回退。后续用户已授权将本组修改与发现 Tab、二级页面整理为中文提交并推送 origin/main；提交定位见 `docs/handoff-modern-secondary-polish.zh.md` 和 Git 日志。原生未验项仍保留，提交不等同于原生验收完成。
