# MioMedia 播放解析与广告校验：专项交接提示词

> 更新：这是提供新版 SDK 前的分析交接。2026-10-12 提供的 `playback.py` 已补齐自研客户端解析，当前实现与验证见 `miomedia-content-playback.zh.md`。平台广告组件与正式环境配置仍待接入，不再把客户端解析缺失列为当前阻塞。

以下内容可完整复制到其他项目的新会话。目标是取得可供 Playra 实施的契约和可重复验证的结果。

---

你正在分析 MioMedia 的正式接入链路。请先核实文件与运行证据，再开展分析。不要修改已经通过自检的 SDK 算法。

## 项目与现状

- Playra：`C:/Users/haige/Desktop/Playra`，Flutter/Dart，目标 Web 与 Android。
- 原始接入包：`C:/Users/haige/Desktop/instruct/tv-reverse-api`，纯标准库 Python SDK，配套 `docs/`、`samples/`。
- SDK 副本：`Playra/tool/source_runtime/vendor/miomedia/`。
- 封装：`Playra/tool/source_runtime/miomedia_adapter.py`。
- 接入说明与接口清单：`Playra/docs/miomedia-sdk-integration.zh.md`、`miomedia-endpoint-inventory.zh.md`。
- Playra 通过外部 Python HTTP 服务调用 SDK；不要把加密实现移到 Flutter，也不要改为每次生成新设备身份。

默认环境已验证握手以及推荐、轮播、目录、详情、剧集、清晰度、播放材料 7 个操作。实际握手严格校验 `deviceSecret` 与本地派生值一致，设备身份在服务重启后复用。正式环境绑定值尚待平台确认，读取现有配置，不把密钥写入报告或客户端。

建议按需要使用 `source-driven-development` 核验 SDK 资料与平台规范，使用 `api-and-interface-design` 定义回接契约，使用 `security-and-hardening` 检查脚本运行边界，最后通过 `verification-and-delivery` 记录实际验证结果。若新项目没有这些 Skill，遵守同样的证据与边界要求即可。

此次需要补齐两个缺口：

1. `resolve/exchange` 返回 `isClientParse=true`、空 `playUrl`、`luaScript` 和 `originalUrl` 时，如何按平台契约取得真实媒体。
2. `resolve/exchange` 返回业务码 `4031` 时，如何完成真实广告观看校验，再继续播放。

## 已确认的请求链与数据

1. `POST /video/detail`，`{videoId}`。当前真实响应的线路位于 `data.video.player[]`，含 `playerCode/playerName/isVip/isVertical`。文档把线路放在 episodes 内，与现场不完全一致。
2. `POST /resolve/episodes`，`{videoId,code}`。返回真实 `episodeNum/episodeName/displayName/sourceId/code/isVip`。
3. `POST /resolve/qualities`，`{videoId,code,episodeNum,caps:[]}`。返回 `qualities/exchangeToken/expiresAt/isClientParse`。
4. `POST /resolve/exchange`，`{videoId,code,episodeNum,quality,exchangeToken,caps:[]}`。兑换令牌绑定作品、线路与集数；文档有效期 300 秒。

默认环境当前可能返回两种情况：

- 客户端解析材料：`isClientParse=true`、空 `playUrl`、有 `luaScript/originalUrl`。
- 广告要求：`code=4031`，`data.adRequired=true`，有 `allowEarlyClose/minWatchSeconds/slotCode/landscapePlacementId/portraitPlacementId`。最近核验的槽位为 `player_switch_episode`。`minWatchSeconds=0` 也不能被解释为已经完成广告观看。

Playra 当前只声明空 `caps`。尚无 `v2ts` 播放实现，禁止为了拿到不同响应而虚报能力。作品 ID 是字符串，不转换为 Bangumi ID 或 JavaScript 数字。以现场响应为准，不按同名作品或显示索引猜测线路、剧集身份。

## 第一部分：Lua 解析契约

阅读 `docs/api/playback.md` 和与脚本执行有关的全部材料，逐项确定：

- luaScript 是明文脚本、编码包装、字节码还是其他格式；如何校验版本和完整性。
- originalUrl 的格式和语义，以及它是否可以直接作为网络地址使用。
- 入口函数名、参数、同步/异步调用方式、返回值 schema、错误语义。
- 运行时版本、需要注入的函数和对象。具体列出网络请求、JSON、编码、加解密、日志、时间等接口；不要凭经验发明函数。
- 是否依赖账号、cookie、设备会话、签名、服务端校时、线路配置或外部接入点。
- HTTP headers、referer、重定向、cookie 与响应编码如何传递到最终媒体请求。
- 返回结果是否包含清晰度、容器格式、有效期、媒体 headers、下一步请求材料或播放模式。

取得脚本样本后，先静态阅读，再根据明确契约制作受限执行验证。不要直接执行完整未知脚本，也不要提供不受限文件、进程或任意网络能力。若材料中没有定义运行时接口，明确列出缺失项，不把猜测作为平台规范。

需要评估两条实施路线，并给出证据：

1. 可以依据明确、稳定的脚本契约用纯 Python 标准库实现等价解析流程。
2. 必须使用 Lua 运行时，则单独说明运行时依赖、Web/Android 经 Python 服务调用的部署方式，以及受限网络、CPU/内存、超时和取消设计。

SDK 仍保持纯标准库；解析运行时若必须增加依赖，置于独立可选模块并明确边界。不要声称任意 Lua 脚本能够由标准库自动执行。

## 第二部分：真实广告校验契约

阅读 `docs/api/ads.md`、错误码说明、相关接口与可用样本，确认：

- `4031` 的触发与解除条件，是否绑定设备、作品、线路、集数或兑换令牌。
- 广告配置、开始、播放进度、完成、关闭、奖励或签名接口的精确顺序、必填字段和响应。
- Android 广告组件或 Web 可支持的官方观看路径；平台是否允许服务端代替客户端进行某些步骤。
- 最短观看时长、允许提前关闭与完成状态的区别。
- 广告完成后的凭证类型、有效期、重放限制以及 qualities/exchange 是否需重新取得令牌。
- 无广告填充、播放失败、取消、离开页面、切换集数、会话失效的处理。

现有 `docs/api/ads.md` 已明确：`player_switch_episode` 槽位标记 `s2sVerify:true`，有效展示以服务端间的回调为准；仅上报 `reportEvent/reportNoFill/reportClose` 不能代替正式展示回调。分析时必须核对广告平台、应用配置与回调校验契约，不能把这些事件接口串联成功当成广告验证完成。

不要伪造广告事件、观看时长、奖励签名或会员权益，也不要轮换设备身份规避 `4031`。若需要平台 SDK、账号或正式配置，应明确列为前置条件，并给出可实施的对接要求。

## 第三部分：媒体播放与平台差异

- 区分直接 mp4/m3u8、客户端解析结果与 v2 HLS。列出各自完整请求链。
- 如需 v2ts，取得 `V2Playlist/V2Segment/V2HlsKey` 的明确格式、密钥与分段处理规范及样本。没有实现并验证之前保持 `caps:[]`。
- 对实际媒体验证 HTTP 状态、Content-Type、HLS 标签或容器格式、有效期与 headers。HTTP 200 的 HTML 错误页不算播放成功。
- 分别说明 Web 的 CORS、浏览器用户点击播放，以及 Android 媒体 headers 与网络限制。
- 如需要媒体代理，说明其职责、URL allowlist、访问鉴权、范围请求、过期和资源清理；不要开放任意 URL 转发。

## 输出给 Playra 的接入契约

请给出一个固定受限操作的建议 schema，至少含：

```text
请求：videoId(string), code(string), episodeNum(int), quality(可选)
结果：
  ready：mediaUrl, headers, format, expiresAt, verifiedVideoId/code/episodeNum
  adRequired：官方广告步骤需要的公开字段与可用能力
  unavailable：稳定错误码、是否允许重试
```

会话密钥、内部签名配置不得返回 Flutter。Lua 原文不应成为播放器参数。明确区分网络重试、业务拒绝、兑换令牌过期、解析失败与媒体加载失败。切换线路时按真实剧集标识重新核对；取消后不能发布旧请求结果。

## 验收与交付

先输出发现的契约、现有资料缺口和最小实施方案，再实现必要的独立验证工具。禁止修改 SDK 的 `transport/suite/block/signature/device/client` 算法链；仅环境值调整限 `profile.py/config.py`，并记录 TODO。

交付：

1. `playback-contract.zh.md`：实际契约、与文档的差异、字段与状态表、正式环境前置条件。
2. 最小可运行验证工具及命令、运行时依赖说明。
3. 脱敏请求/响应样本：只保留字段、结构、非敏感示例；删除设备身份、密钥、账号令牌、临时兑换令牌和媒体访问令牌。
4. 测试覆盖：真实媒体成功、4031 正常流程、用户取消、超时、令牌过期、错误脚本与切换集数。
5. SDK 自检 `SELFTEST ALL PASS`，算法文件哈希对比；正式播放必须有真实媒体证据。
6. Playra 回接说明：修改文件建议、固定接口 schema、无需修改的模块、尚未验证的 Web/Android 差异。

区分 PASS、PARTIAL、FAIL、BLOCKED。没有最终媒体地址或广告正式接入资料时，不宣称播放器已经接通。文档和新增代码使用中性接入表述，不写未经证据支持的结论。
