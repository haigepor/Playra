## ADDED Requirements

### Requirement: Single playback session
系统 SHALL 在新版资料与播放入口使用单一媒体会话，未选源时不初始化媒体；保留原有路由参数与旧版页面。

#### Scenario: Enter with metadata only
- **WHEN** 从发现、日历或追番携带 BangumiItem 进入
- **THEN** 展示封面和真实选源入口，源选择成功后在同一播放器区域播放

#### Scenario: Read while playing
- **WHEN** 切换三个标签或打开资料和选集弹层
- **THEN** 不调用媒体初始化，不丢失播放进度

### Requirement: Episode identity and cancellation
系统 SHALL 保留原始剧集身份，快速切集仅最后请求生效；跨源不使用相同列表序号自动恢复。

#### Scenario: Switch source with uncertain mapping
- **WHEN** 选择另一个来源
- **THEN** 明确选择目标集后从头播放，取消旧解析和弹幕请求

#### Scenario: Reverse episode view
- **WHEN** 用户降序或切换分段后点击剧集
- **THEN** 回调仍指向原始路和集索引，保留 SP/OVA 等标题

### Requirement: Honest content states
系统 SHALL 区分本集讨论与整部评价，保留登录、隐藏评分、重试、分页和无投票状态。

#### Scenario: Unknown discussion mapping
- **WHEN** 当前剧集不能可靠映射到 Bangumi 正片
- **THEN** 显示未匹配状态，不把列表索引当成真实集号

#### Scenario: Missing backend capabilities
- **WHEN** 未配置弹幕凭据或没有对应评论互动接口
- **THEN** 不提供伪造成功的输入、点赞或回复功能

### Requirement: Platform and visual compatibility
系统 SHALL 保留离线、历史、全屏、PiP、键盘和生命周期策略，支持窄屏和大字体。

#### Scenario: Offline missing media
- **WHEN** 离线文件缺失
- **THEN** 显示真实错误与恢复入口，不假装在线播放

#### Scenario: Accessible assets and controls
- **WHEN** 使用六张 SVG 和新版内容区
- **THEN** 装饰排除语义且不覆盖控件，触控目标至少 48 dp，提供真实尺寸预览和验证记录
