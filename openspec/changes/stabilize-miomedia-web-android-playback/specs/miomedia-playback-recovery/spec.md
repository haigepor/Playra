## ADDED Requirements

### Requirement: Platform-safe media headers
Web SHALL 经同源网关发送媒体请求头，并传递空 Media httpHeaders；Android SHALL 保留真实原生媒体请求头。

#### Scenario: Web source requires headers
- **WHEN** 播放响应包含 User-Agent 或 Referer
- **THEN** Web 不触发非空 Media 请求头异常，网关仍接收到来源头部

### Requirement: Shared episode cache
系统 SHALL 按作品和线路缓存五分钟的剧集结果，并合并同一会话内相同线路的在途请求。

#### Scenario: Rapid line selection
- **WHEN** 用户快速 A→B→A，A 的读取尚未完成
- **THEN** A 复用同一次请求，旧 UI 结果不覆盖 B，新 A 可获取完整结果

### Requirement: Bounded identity-safe recovery
系统 SHALL 首先尝试用户选择，失败后最多尝试两个匹配同一集的候选线路；SHALL 使用候选的真实 episodeNum，并在 ad_required 时结束自动恢复。

#### Scenario: Named special episode
- **WHEN** 原线路的特辑编号为 12，目标线路同名唯一特辑编号为 99
- **THEN** 换线请求使用 99，并保持同一个作品字符串 ID

#### Scenario: Ambiguous or missing mapping
- **WHEN** 目标线路只有相同数组位置或存在多个同名剧集
- **THEN** 不自动替换该剧集，保留手动选择入口

#### Scenario: Cancelled or denied playback
- **WHEN** 新选择取消旧请求或 SDK 返回 ad_required
- **THEN** 不打开迟到媒体、不重置身份、不重复实现 SDK 凭证流程

### Requirement: Playback state marker
当前集三柱标记 SHALL 仅在播放器真实播放且非缓冲、有进度时运动；SHALL 支持暂停、减少动画、后台和释放。

#### Scenario: Pause and reduced motion
- **WHEN** 用户暂停或系统开启减少动画
- **THEN** 标记停止运动，选集卡片尺寸和文字位置保持不变

### Requirement: Evidence-separated validation
报告 SHALL 分别记录接口、传输、解码和真机状态；不得以 HTTP 200 推断全部线路可播放。

#### Scenario: Upstream HLS cannot decode
- **WHEN** 直链可读但浏览器没有解码帧
- **THEN** 报告播放未通过，并检查有限恢复或明确错误提示
