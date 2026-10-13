## ADDED Requirements

### Requirement: Classified source identity
系统 SHALL 区分来源领域与接入方式，保留显式 anime 规则及旧 JSON，并独立保存用户分类覆盖、启停与性能统计。

#### Scenario: Anime sources cannot serve screen works
- **WHEN** 当前作品领域为 screen
- **THEN** anime-only 来源不参加检索或播放调度，未知来源不伪装为动漫

#### Scenario: Remote update preserves preferences
- **WHEN** 来源规则更新且稳定身份不变
- **THEN** 独立用户覆盖不丢失，旧版本性能样本不作为新版本实测结果

### Requirement: Available work candidates
系统 SHALL 仅将匹配作品且具有效剧集的候选展示为播放来源，区分无资源与临时错误、验证要求。

#### Scenario: Missing resource
- **WHEN** 来源确认无匹配作品或无目标集
- **THEN** 普通播放候选隐藏该来源，规则管理仍保留该来源

### Requirement: Measured and bounded automatic playback
系统 SHALL 基于近期耗时及可靠性优选候选，自动恢复最多 3 个候选且临时错误每候选最多追加重试一次，遵循总预算及取消。

#### Scenario: Manual intent replaces recovery
- **WHEN** 用户改集、人工换源或离开会话
- **THEN** 旧恢复与旧媒体回调不能提交结果，也不能改变新目标

#### Scenario: Episode identity is uncertain
- **WHEN** 跨源对应集无法唯一确认
- **THEN** 不按列表位置自动恢复，保留手工确认入口

### Requirement: Media failure and HTTP resolution
系统 SHALL 将媒体初始化失败纳入可重试状态，支持配置 HTTP resolve 服务并复用取消、鉴权请求与标准解析结果。

#### Scenario: URL resolves but media fails
- **WHEN** 解析成功但媒体初始化失败
- **THEN** 显示明确失败并在自动模式的预算内尝试备用候选

#### Scenario: Algorithm service returns media
- **WHEN** HTTP 请求配置及 JSONPath 映射返回有效媒体 URL
- **THEN** 使用唯一播放器播放，保留媒体 headers、format 和有效期，不在公共统计中输出凭据
