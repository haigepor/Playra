## Context

视觉和状态矩阵以 `docs/design/modern-player-detail.zh.md` 为唯一详细设计。迁移后仓库为 D:\project\Playra，基线 acdcbab8，开始时工作区干净。Flutter 3.47.6 / Dart 3.13.5，使用当前 Flutter 组件体系。

## Goals / Non-Goals

**Goals:** 单一播放会话，选源后原位播放，独立详情/讨论/评价内容，真实剧集身份与状态，可访问的资料、选集和下载入口。

**Non-Goals:** 不修改根导航动画，不移除旧页，不替换播放器内核、不迁移历史、不做无缝换源，不配置弹幕凭据，不宣称没有设备证据的原生验收。

## Decisions

1. 将 VideoPage 的媒体生命周期外壳提取为共享 PlaybackScaffold；旧 VideoPage 成为兼容包装，新页面以内容构建器使用外壳。拒绝嵌套 InfoPage/VideoPage，避免两个页面各自持有生命周期。
2. info/video 路由均通过 InterfacePageHost 选择视图。路由作用域提供一套 PlayerController、VideoPageController、InfoController；资料态不调用 applyPlaybackArgs/init。选源得到完整 OnlineVideoPlaybackArgs 后显式接入并启动。
3. SourceSheet 增加可选结果回调，旧调用保持 pushNamed 行为。换源先确认目标原始索引；保守要求用户选集，从头播放，绝不跨源套用旧位置或进度。首次历史恢复须校验来源和 URL/标题身份。
4. 固定播放器外壳与下方内容兄弟布局，标签和弹层仅改变内容状态。共享全屏/PiP/返回/键盘/系统栏行为保留。
5. 新版选集用原始路/集索引，50 集分段、惰性网格和显式定位；浏览线路不触发切集。播放标记同时要求 playingEpisode 匹配与真实 playing。
6. 复用真实追番、评价编辑、下载和评论组件；未知特别篇讨论不得退回列表序号冒充正片。请求失败、空、未匹配分别呈现。
7. 六张 SVG 先作 XML/UTF-8/Flutter 渲染审查和 HTML 实际尺寸预览，再用于新页面。不会用 HTML 截图证明媒体已播放。

## Risks / Trade-offs

- [移动平台生命周期回归] → 最小提取既有外壳，跑现有布局/全屏/会话测试；原生设备证据单列。
- [换源保存错历史] → 保留旧历史身份到 stop 完成，再安装新来源；取消所有旧异步会话。
- [异步资料失败影响媒体] → 两套数据状态隔离，局部重试，不整页替换。
- [少量来源无法可靠匹配] → 明确选集，放弃自动跨源恢复优先保证正确性。

## Migration Plan

依次完成素材、共享外壳、路由与新内容、回归和交付。运行时切回旧界面可恢复旧呈现；代码回退以本任务 diff 相对 acdcbab8 为范围，保留其他工作。不重写提交历史。

## Open Questions

无新增产品决策。Android 设备、可用媒体和验证码只能以实际环境证据确认。
