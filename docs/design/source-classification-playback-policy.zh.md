# 来源分类归档与播放调度逻辑审查

日期：2026-10-11。项目：`C:/Users/haige/Desktop/Playra`。

本文保留实施前的源码研究与建议，后面的“现有逻辑”和行号属于研究时快照。2026-10-11 已按确认开始实施，当前行为、修改文件和验证边界见 `docs/verification/classified-playback-sources.zh.md`；下方建议不能当作全部已经实现。

## 1. 本机来源归档

核对文件：`C:/Users/haige/AppData/Roaming/com.example/kazumi/plugins/v2/plugins.json`。

共 16 条规则，全部显式声明 `type: anime`；14 条采用 XPath 搜索和剧集提取，2 条采用 JSON API。按站点地址去重为 15 个站点。Web、Android 存储独立，此清单不能代表其安装状态。未逐站测可用性或解析速度。

| 名称 | 基础站点 | 版本 | 搜索/剧集模式 | 分类归档 |
|---|---|---|---|---|
| 7sefun | https://www.7sefun.top/ | 1.3 | xpath / xpath | 动漫；内置来源名称 |
| DM84 | https://dmbus.cc/ | 1.4 | xpath / xpath | 动漫；内置来源名称 |
| xfdmnext | https://next.xifanacg.com/ | 1.1 | api / api | 动漫；额外安装/导入 |
| MXdm | https://www.dcc3.com | 2.4 | xpath / xpath | 动漫；额外安装/导入 |
| dalvdm | https://www.sbdl.cc/ | 1.1 | xpath / xpath | 动漫；额外安装/导入 |
| moonci | https://www.moonci.com/ | 1.0 | xpath / xpath | 动漫；额外安装/导入 |
| mutefun | https://www.2kdm.com/ | 1.2 | xpath / xpath | 动漫；额外安装/导入 |
| aafun | https://www.moonci.com/ | 1.2 | xpath / xpath | 动漫；额外安装/导入 |
| akianime | https://www.akianime.cc/ | 1.4 | xpath / xpath | 动漫；额外安装/导入 |
| ezdmw | https://m.ezdmw.org/ | 1.2 | xpath / xpath | 动漫；额外安装/导入 |
| giriGiriLove | https://ani.girigirilove.com | 2.4 | xpath / xpath | 动漫；额外安装/导入 |
| sorani | https://www.sorani.net/ | 1.0 | api / api | 动漫；额外安装/导入 |
| mgnacg | https://www.mgnacg.com | 1.0 | xpath / xpath | 动漫；额外安装/导入 |
| xfdmneo | https://dm1.xfdm.pro/ | 1.1 | xpath / xpath | 动漫；额外安装/导入 |
| baimao | https://www.baimaodm.com/ | 1.0 | xpath / xpath | 动漫；额外安装/导入 |
| AGE | https://www.agedm.io/ | 1.5 | xpath / xpath | 动漫；额外安装/导入 |

存储未记录每条额外规则最初是手工编辑、文件导入还是商店安装，不虚构来源历史。moonci 与 aafun 同站但规则不同，保留独立身份，并在请求调度时共享站点并发额度。规则 `api` 字段是兼容协议级别，不是 HTTP 类型、速度或清晰度。

## 2. 已核实的现有执行链

```text
ModernPlayerDetailPage.chooseSource
  -> SourceSheet.initState
  -> PluginSearchService.queryAllSource（全部已安装规则，最多 4 个并发）
  -> Plugin.queryBangumi -> SourceService.search -> RuleEngine
  -> 用户选择某个搜索结果
  -> Plugin.queryChapterRoads -> SourceService.lines -> RuleEngine
  -> 确认集数 / 核对同来源历史
  -> PlaybackScaffold.startSource -> VideoPageController.switchOnlineSource
  -> changeEpisode -> SourcePlaybackService -> 平台 WebView 解析
  -> PlayerController.init -> 媒体打开
```

核对位置：

- `lib/services/plugin/plugin_search_service.dart:59`：复制整个 `pluginList`，未按内容类型过滤；4 个工作者按配置顺序取任务。
- `lib/pages/info/source_sheet.dart:184`：为每个已安装规则创建展示分组。搜索完成顺序只影响第一个结果分组的展开，未用于自动播放。
- `lib/pages/info/source_sheet_view.dart:139`：包含所有分组；无结果、错误、验证码仍有来源行和对应状态。
- `lib/pages/info/source_sheet.dart:121`：点击搜索条目后才取剧集；仅检查线路集合是否为空，没有形成“当前作品、当前集可用”的预筛选目录。
- `lib/services/source/source_models.dart:47`：来源 manifest 有身份与能力，缺少来源支持的多内容领域、接入种类和选择策略。
- `lib/services/source/source_service.dart:206`：搜索条目的分类来自整条规则的 `type`。综合来源中的每个作品不能因此自动获得正确类型。
- `lib/services/source/source_service.dart:82`：健康状态是内存中的最近一次分阶段结果与耗时，没有统计窗口、首帧时间、稳定性评分或自动调度。
- `lib/services/plugin/plugin_validity_tracker.dart`：只记录本次启动是否曾返回搜索结果，不代表某部作品有资源，更不代表某集能播放。

现有首页目录默认适配仅覆盖 DM84、7sefun；本机额外规则没有 `sourceConfig.catalog`。规则已安装、支持搜索、支持首页目录、当前作品有资源、当前剧集可播放，是不同条件。

## 3. 重试与切换审查

| 检查项 | 当前证据 | 判断 |
|---|---|---|
| 请求取消和过期结果 | 查询和播放使用 AsyncSession；解析替换、离开会取消旧请求 | 已有基础，继续复用 |
| 解析超时 | Native 默认解析 15 秒；Web 至少 45 秒；播放外层上下文 55 秒 | 已有边界，但不能理解为完整首帧超时 |
| 自动换线路/换来源 | 视频解析异常只设置页面错误；没有遍历候选来源的调度器 | 尚未实现用户要求 |
| 自动播放下一集 | player_item 的完成处理会切下一集，并避免定时器反复重试 | 属于连播，不属于故障恢复 |
| 手动重新检索 | 支持原词、别名、自定义词、验证码完成后重查 | 已有能力，需统一会话与状态 |
| 手动重新解析 | 新版错误行“重试”再次调用 changeEpisode | 有入口，但没有明确捕获当前实时进度 |
| 手动换来源 | 重新打开 SourceSheet，并重新确认目标集 | 防误播合理，但重复检索且换源后默认 offset 为 0 |
| 同来源历史恢复 | verifiedResume 核对作品、规则、详情地址与唯一剧集 URL | 保留，不能退回旧索引恢复 |
| 跨来源集数恢复 | 当前要求手工确认目标集 | 安全但尚无可靠映射后的自动续播 |
| 媒体初始化失败 | PlayerController.init 捕获创建失败后返回 false；视频控制器取消会话但未设置 _failLoading | 页面错误状态与重试入口可能缺失 |
| 播放期间媒体错误 | player.stream.error 显示 Toast/日志 | 尚未接入统一恢复策略 |
| 错误细分 | 剧集缺失、格式变化等多被包装为 SOURCE_ERROR/ChapterErrorException | 无法可靠区分“没资源”和“临时失败” |

相关文件：`video_controller.dart:420,479,630,686`，`modern_player_detail_page.dart:281,702`，`playback_identity.dart:8`，`player_controller.dart` 的 init，`player_playback_controller.dart:437`，`source_playback_service.dart`。

额外一致性点：验证码采集结果的 `applyHarvestedSearchResult` 直接发布结果，没有显式作废同来源正在进行的旧查询，存在被稍后旧结果覆盖的可能；后续需让采集与重查共用同一查询代次。

## 4. 分类与扩展契约建议（待实施）

不要把“规则技术类型”“内容分类”和“规则来源历史”混在一个 `type` 中。

| 维度 | 建议字段 | 作用 |
|---|---|---|
| 稳定身份 | providerId / sourceId | 更新、改名、历史和统计关联 |
| 内容领域 | domains: anime / screen | 动漫和影视来源隔离；允许综合来源声明多个领域 |
| 支持内容类型 | mediaKinds | 动漫系列、电影、电视剧、综艺、纪录片、漫剧等能力声明 |
| 接入方式 | adapterKind: rule / http / registered | 配置规则、标准 HTTP、已注册算法适配器 |
| 获取方式 | searchMode / chapterMode | XPath 或 JSON API，复用现有 RuleEngine |
| 安装来源 | origin | bundled / store / imported / custom；未知历史保持 unknown |
| 用户策略 | enabled / selectionMode / preferredProviderId | 启停、自动最快、手动固定来源 |
| 执行能力 | capabilities | catalog / search / episodes / resolve 等真实支持项 |

这 16 条已明确归入 anime，仅参与动漫作品检索和播放。新增影视作品只调度明确支持 screen 及对应类型的来源；综合来源按作品资料和来源响应逐条判断，未知分类不混入确定分类页面。动漫电影应保留 `domain=anime, format=movie`，避免所有 movie 被排到影视而从动漫消失。

迁移保留旧 `type` 和 JSON 导入导出。不要依据 Plugin.fromJson 的缺失字段默认 anime，将今后所有未分类自定义源强行归为动漫。未知来源在管理页要求补分类。

用户启停、分类覆盖、固定来源与性能统计建议单独保存为按 providerId 索引的本地设置，不直接依赖远程规则正文。当前 PluginsController._replacePlugin 只保留 sourceId，远程更新会整体替换规则对象；仅写在 sourceConfig 中的本地偏好可能丢失。规则本身声明与用户覆盖分别管理。

## 5. 自定义 HTTP / 算法接入

已有 ApiRequestConfig 支持 GET/POST、headers、query、JSON/form 请求体；搜索和剧集可用 JSONPath 与模板变量适配。它不是任意签名/加解密脚本执行器。

已有 SourceHttpClient 是统一 API 的调用工具；本轮检索未发现页面通过它注册远程来源。SourceHttpServer 的播放任务仍经浏览器解析网关，不能因此认为任意远程 resolve API 已接入本地播放器。

建议建立统一 SourceAdapter 契约，返回相同的作品、线路、剧集和解析结果：

```text
manifest / search / getContent / getLines / resolve
resolve -> url 或受保护媒体引用、headers、format、expiresAt
```

- rule：现有 SourceService + RuleEngine；WebView 解析保持平台适配。
- http：用户填写 base URL、鉴权引用及字段映射，支持直接媒体/标准 resolve 结果；仍走统一播放器初始化。
- registered：复杂签名、参数算法由注册的实现或用户部署的 HTTP 服务负责，再转换为统一 DTO。移动客户端不执行未知来源脚本。
- 所有适配器接收同一取消、超时、来源身份和会话上下文；凭据、Cookie 留在受控执行边界，不进入规则展示、统计或公共 JSON。
- 能力按实际实现声明；只支持搜索的接口不能对外宣称支持播放。

提供 HTTP API 与接入第三方 HTTP API 是两个方向，需同时覆盖，不能只做输出端接口。

## 6. 只显示当前作品有资源的来源

使用作品级可用性状态，不删除规则，也不把空结果写成全局来源失效：

```text
unknown -> searching -> matched -> episodesReady -> resolved -> playable
                  \-> noMatch
                                 \-> episodeMissing
任一请求可进入 temporaryError / challengeRequired / cancelled
```

- 常规播放来源列表只展示作品匹配通过且存在有效剧集的来源；换源恢复时再限制为当前目标集存在。
- 仅搜索到同名条目不算有资源。优先稳定作品 ID；其次校验标题/别名、季、年份、类型，候选不唯一或证据不足就要求确认。
- 确认无匹配/缺集的规则不展示为可播放项；超时、验证码、网络失败属于未知或暂不可用，不归入“没有此资源”。
- 顶部显示聚合进度，如“已找到 3 个来源，仍在检索”；异常来源放在可展开的诊断区，提供验证或重试。
- 规则管理仍显示全部 16 条，按动漫/影视/未分类分组，并显示接入方式、启停、近期实际表现。
- 缓存按 providerId、规则版本、作品身份、目标集和平台/网络上下文隔离；无资源负缓存短期有效，新番更新、用户刷新或规则更新可作废。禁止将一次无结果永久隐藏。
- 有剧集目录不保证每一集都能解析，页面区分“已匹配剧集”和“已验证可播放”。无需预解析全部作品和全部集数。

## 7. 优先最快可用来源的调度建议

目标是同一作品、同一集下最快稳定开始播放，不能按搜索耗时、固定规则名或 HTTP 200 来判定最快。

记录各阶段：搜索、取剧集、视频解析、媒体打开至首帧、播放失败/持续缓冲；按平台、网络环境、来源与线路统计。现有 elapsedMs 可复用为阶段样本，需增加有限近期窗口、持久化、样本数和规则版本失效策略。

```text
分类/能力过滤
  -> 校验作品及目标集
  -> 排除本轮已失败候选与冷却中的自动候选
  -> 按近期成功率、解析+首帧预计耗时及样本可信度排序
  -> 优先尝试最高候选
  -> 达到预设等待阈值且平台允许时尝试备用
  -> 在唯一播放器上打开媒体并验证开始播放
  -> 提交当前来源、剧集身份与进度
```

冷启动没有样本时使用明确的默认优先级、受限探测和少量探索；不能标注某来源“最快”。用户固定来源时优先该来源，自动降级是否允许由选择模式决定。成功后不因其他候选稍快而中途抢占。

保留现有搜索并发上限 4 作为初始值。解析并发默认保守，最多尝试少量候选；平台支持独立解析器时可实现延迟启动备用的竞争，结果返回后取消输家。Native/Web 需分别验证。

当前单个 SourcePlaybackService/WebView 服务会取消自己的前一请求，并串行执行。不能对同一个实例 Future.any 两个解析；如需要竞争，建立独立解析实例与请求代次，参考现有下载池结构，但不占用下载会话或并行初始化多个播放器。同域来源共享请求限额。

配置分别限制单次请求、单候选首帧等待、整个恢复流程时长和最大候选数；Web 现有 45 秒解析边界应纳入预算，不能直接套用 Native 超时。媒体首帧超时不得把用户主动暂停或页面退到后台误判为故障。

## 8. 自动与手动恢复状态机建议

共享状态机：`idle -> matching -> resolving -> opening -> playing -> recovering -> failed`，每次人工操作产生新 intentId，旧请求和旧回调不得提交。

| 事件 | 自动模式 | 手动模式 |
|---|---|---|
| 没有此作品或目标集 | 跳过该候选，不反复重试 | 不显示为可选播放项 |
| 临时网络/解析超时 | 同候选有限重试，再尝试同集备用线路/来源 | “重试当前来源”，明确保持当前集 |
| 地址过期或鉴权上下文变更 | 作废媒体缓存并重新 resolve | 手动刷新解析，不重复使用失效地址 |
| 媒体打开失败或首帧超时 | 反馈候选失败，再按预算换候选 | 展示媒体失败状态与换源入口 |
| 验证码 | 排除无人值守重试，允许尝试其他候选 | 显示完成验证入口 |
| 取消/退出/用户新选择 | 立即终止旧恢复流程，不计失败 | 最新操作优先 |
| 无法确定跨源对应集 | 停止自动提交并请求确认 | 展示目标集选择，默认不套用旧位置 |
| 全部候选失败 | 停止重试，显示聚合原因 | 提供重试本轮和修改检索词 |

初始策略可以限制每个候选一次额外临时错误重试、每轮最多尝试少量候选，再根据实际测量调整；数值须写入实施契约。每轮维护已尝试 provider/content/line/episode 集合，避免 A/B 来回循环。退避与站点冷却必须可被人工选择取消或覆盖，并区分取消与故障。

切换同一集前捕获实时 position，而不是使用默认 offset=0。跨来源仅对唯一可信的正片/季/集映射恢复进度，并在新媒体时长已知后校验范围；剪辑差异过大或 SP/OVA/合集无法匹配时要求确认。电影使用电影作品身份，不能套用 series 的第 1 集匹配。

手动固定来源期间自动流程不能抢占；手动改集会取消整轮恢复，不能让旧解析将页面带回上一集。全部候选失败时保留目标集和尝试明细，避免显示成功但黑屏。离线播放不自动混入在线回退，缺文件保留明确错误与在线入口。

## 9. 实施顺序与验收

1. NEXT：来源 manifest、内容领域、用户覆盖与迁移；16 条 anime 分类从现有声明迁移；未知源保持未知。
2. NEXT：作品与目标集候选目录、可用性状态、缓存；普通来源列表隐藏确认无资源项。
3. NEXT：统一错误与媒体打开失败状态，接入实时进度和唯一剧集映射；先补手动重试闭环。
4. NEXT：统计与受限自动选择、失败回退、冷却/预算；新旧页面与 HTTP 路径共用策略。
5. NEXT：接入 HTTP/注册算法适配器及规则管理分组，补鉴权、媒体地址有效期与能力声明。

后续验证应覆盖：动漫来源不进入影视调度；综合来源逐条分类；空结果/错误/验证码区分；同名不同季拒绝误匹配；SP/OVA/倒序不改变身份；搜索快但视频失败不能获胜；解析成功但媒体失败进入恢复；自动预算耗尽终止；人工切源切集取消旧自动流程；跨源进度与时长校验；规则更新保留本地覆盖；Web 用户点击播放；Android/Windows WebView 独立性；HTTP 与应用策略一致。

研究结论：已有共享规则执行、会话取消、阶段健康记录和保守历史恢复基础，但尚未形成分类过滤、当前作品可用来源筛选、最快首帧选择及自动回退闭环。本次未运行构建、播放测试或站点测速；以上现状来自源码与保存配置，建议算法尚未实施。
