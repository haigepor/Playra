## Why

MioMedia 换取成功仍可能在 Web 播放器创建、HLS 解码或媒体加载阶段失败，现有页面只提供手动重试。用户要求优先完善 Web 和 Android，并让播放中的选集标记呈现真实状态。

## What Changes

- 修复 Web Media 非空请求头异常，继续经同源媒体网关传递来源请求头，Android 保留原生请求头。
- 增加页面会话内剧集缓存与请求合并，取消选择不丢弃可复用的剧集结果。
- 增加有限次数的播放恢复：手动选择优先，后续按近期实测耗时选择候选；严格匹配同一集，禁止用数组位置推断。
- 将开始播放、缓冲、暂停、失败与成功状态分开；三柱标记仅在真实播放时运动，并尊重减少动画和应用后台状态。
- 核验 Aliplayer 集成条件。当前保留 media_kit；没有授权配置时不添加商业播放器依赖或虚构 License。
- 分别记录接口成功、媒体传输验证、浏览器解码与 Android 真机结果。

## Capabilities

### New Capabilities
- `miomedia-playback-recovery`: Web/Android 的安全换线、剧集缓存和播放状态标记。

### Modified Capabilities
无；现有接口字段、凭证策略和其他播放器入口保持兼容。

## Impact

影响 MioDetailPage、其专用恢复协调器与播放标记组件、相关测试及核验报告。不修改 Python SDK 算法、设备身份、账户数据或全局依赖。Web 构建和原生 Flutter 编译覆盖同一播放恢复逻辑；实际 Android 解码仍需要可用设备验证。
