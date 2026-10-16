## ADDED Requirements

### Requirement: 独立SDK本地个人库
系统 MUST 按providerId及contentId保存独立SDK收藏和逐集观看状态，不伪造Bangumi ID、不迁移或清理旧历史收藏及自定义规则。分集 MUST 保留真实线路code及reference/number/name；不得持久化媒体URL、请求头或凭证。删除历史和取消收藏 MUST 彼此独立。

#### Scenario: 重启后继续观看
- **WHEN** 用户实际播放独立SDK第99集并退出或重启客户端
- **THEN** 首页、历史页和收藏页展示保存的真实集及进度
- **AND** 进入详情恢复对应线路与集，只准备新的短效链接，点击播放后按时长校验恢复进度

#### Scenario: 准备和隐私模式
- **WHEN** 仅准备播放、解析失败或处于隐私模式
- **THEN** 不新建或更新观看历史
- **AND** 用户主动收藏仍可保存收藏状态

#### Scenario: 历史线路失效
- **WHEN** 历史手动锁定线路或对应分集已经不存在
- **THEN** 提示用户重新选择，不静默跳首集或其他线路

### Requirement: Independent manual quality selection
The application SHALL expose only declared quality tiers and SHALL keep manual resolution selection independent from line locking. Lumina automatic resolution SHALL prefer 4K then 1080p. Explicit quality requests MUST NOT silently switch resolution or unlock a manually selected line.

#### Scenario: User selects 1080p on a locked line
- **WHEN** an anime episode is playing on a manually locked line and the user selects 1080p
- **THEN** the provider, line and original episode SHALL remain selected and the new media SHALL restore compatible playback progress and pause state.

#### Scenario: User restores automatic quality
- **WHEN** a manual line remains selected and the user selects automatic quality
- **THEN** the line lock SHALL remain unchanged and only the resolution preference SHALL reset.

#### Scenario: Quality is absent for a new episode
- **WHEN** a manually selected resolution is unavailable on the newly selected real episode
- **THEN** the application SHALL explain the missing tier without silently selecting its first episode or claiming another resolution as the requested one.

#### Scenario: An earlier quality request returns late
- **WHEN** a newer quality selection supersedes a pending request
- **THEN** the old result SHALL NOT replace the newer selection or install stale media.

#### Scenario: An episode is prepared before playback starts
- **WHEN** a user selects episode 99 and only prepares its link
- **THEN** the inline episode window and episode-sheet segment SHALL follow that selected episode rather than the first episode or the previously installed media.

### Requirement: Prepare without automatic media playback
Online detail entry SHALL resolve the selected episode to a prepared media URL automatically, but MUST NOT open or start the media player until explicit user playback intent.

#### Scenario: User opens an online detail page
- **WHEN** source detail and a valid selected episode are available
- **THEN** one complete resolution SHALL start, media open count SHALL remain zero, and the UI SHALL distinguish preparation from playback.

#### Scenario: User clicks while preparation is running
- **WHEN** the user requests playback before that same episode preparation completes
- **THEN** the application SHALL share the pending request and open only the current selected episode once.

### Requirement: Short lived identity bound preparation
Prepared media SHALL be held only in page memory and bound to SDK, work, real line, real episode, quality and generation. Expired URLs SHALL be refreshed on consumption.

#### Scenario: A prepared URL becomes stale
- **WHEN** the user clicks after its expiry or conservative fallback TTL
- **THEN** the application SHALL resolve fresh media instead of opening the stale URL.

#### Scenario: Old preparation completes after episode switch
- **WHEN** episode A finishes after switching to episode B
- **THEN** A SHALL neither replace B preparation nor open a player nor change history or playing state.

### Requirement: Preserve explicit switching intent
Manual source lock and same episode switching SHALL remain intact. Before playback, switching SHALL only prepare; after explicit playback intent, switching SHALL preserve that intent.

#### Scenario: User switches a line before starting
- **WHEN** no playback intent exists and a line is selected manually
- **THEN** only that line SHALL be prepared and no automatic cross-source playback SHALL occur.

#### Scenario: User continues a historical episode
- **WHEN** a verified history entry identifies episode two and progress
- **THEN** detail SHALL prepare episode two without playing and SHALL restore verified progress only after the user starts playback.

### Requirement: Preparation is not playback success
Preparation MUST NOT report first-frame success, write watching progress, or alter saved favorites. Media failures and resolution failures SHALL remain distinct.

#### Scenario: URL resolves but media cannot decode
- **WHEN** prepared media later fails to open
- **THEN** the system SHALL retain a media failure and SHALL NOT report prior preparation as a successful playback verification.

#### Scenario: Parser returns a known plain text rejection
- **WHEN** an upstream resolver returns HTTP 200 with its known no-playback-address business message
- **THEN** the host SHALL classify it as unavailable content rather than malformed JSON, reveal no upstream payload, and offer retry and explicit line selection without silently releasing a manual lock.

#### Scenario: No declared selectable quality
- **WHEN** the current line has no declared resolution tiers
- **THEN** the page SHALL avoid a redundant quality choice and SHALL NOT claim to use a direct link merely because quality metadata loaded.
