# AniFive 四源动漫接入分析

日期：2026-10-15。阶段：分析完成，尚未实施业务代码替换。

分析基线：Playra `37501c88efff`；外部 SDK `dc13fdb`，目录为 `C:\Users\zhuyi\Desktop\tv-reverse-playra-16rules-api`。本文件中的在线结果是本机当次抽样，不代表全站、全线路或 Web/Android 播放验收。

## 1. 已确认需求与接入结论

用户已确认：以当前 SDK 的 **A/B/C/D 四源**为准，将 Playra 默认内置的 16 条动漫来源替换为这四源，不补造第五源。本轮要求先分析。

成功标准应为：新装默认四源；旧安装完成可回滚迁移；四源进入现有动漫搜索、Bangumi 详情、选集、播放、历史、收藏和支持平台的下载流程；Web 与 Android 使用同一业务契约；真实媒体播放验收通过。

推荐实现是 **一个 AniFive Python SDK + 四个受控 Runtime Adapter + 四份动漫 API 规则**。四份规则负责声明和数据映射，站点解析由 SDK 承担。这样可复用当前 `RuleContentProvider` 动漫入口，不必将动漫迁入主要服务影视、漫剧和剧集的通用 `SdkDetailPage`。

现有 Mio SDK 保留其业务范围。此次收敛的是内置动漫来源，不是删除所有 SDK、Bangumi 元数据或用户自定义规则。

## 2. 数量与能力口径

| 对象 | 当前/目标 | 说明 |
| --- | --- | --- |
| 当前内置动漫规则 | 16 | 14 条 XPath、2 条 API 规则 |
| 新增外部 SDK | 1 个 | Python 包 `anifive`，不是四个 SDK |
| SDK 来源 | 4 个 | `Client.SOURCES` 只有 A/B/C/D；目录名和 AniFive 名称不代表五源 |
| SDK 核心内容能力 | 4 类 | `search`、`detail`、`episodes`、`play` |
| SDK 辅助能力 | 2 类 | `check_quality`、`fallback`；另有配置/切源方法 |
| Playra 建议运行时业务契约 | 3 类 | `search`、`episodes`、`resolve`，每源一组，共 12 个来源路径实例 |
| 接入后真实内容 SDK | 2 个 | 原有 Mio + 新增 AniFive；规则引擎和 Bangumi 数据接口另计 |

`detail` 与 `episodes` 在 SDK 内会重复获取详情；适配层宜一次读取详情并转换全部可用线路。`check_quality` 是媒体探测，不是可选画质列表；不能据此声明支持多档画质。`fallback` 是串行搜索并返回首个非空来源，不是同作品同集播放故障切换。

SDK 没有完整番剧资料、首页目录、分类榜单及上游分页接口。Bangumi 资料必须继续使用；搜索应明确单页语义，不能反复请求第一页冒充翻页。

## 3. 四源映射及在线抽样

四个 `HOST_SOURCE_*` 配置均为空，默认 `Client()` 实测抛出 `RuntimeError`。下列域名来自 Playra 现有规则，测试时通过构造参数临时传入，没有修改 SDK 配置。

| 来源 | 对应现有规则/主机 | SDK 播放方式 | 本次证据 |
| --- | --- | --- | --- |
| A | DM84 / `dmbus.cc` | 播放页 → iframe 面板 → 即时参数 → 解析服务 | 搜索“斗罗大陆”14 条；首个作品《斗罗大陆2：绝世唐门》1 线路、174 条剧集；解析并读取 HLS 头部成功 |
| B | MXdm / `www.dcc3.com` | 播放页提取 ArtPlayer 清单 | 同关键词12 条；首个作品《斗罗大陆5重生唐三》1 线路、93 条剧集；读取 HLS 清单成功 |
| C | akianime / `www.akianime.cc` | 固定线路2，解码 `player_aaaa` | “斗罗大陆”空；“海贼王”10 条；《海贼王》2 线路各1180条，SDK支持的线路2解析并读取 HLS 头部成功 |
| D | moonci / `www.moonci.com` | 站内播放页 → 播放面 ID → 边缘签发 | “斗罗大陆”空；“海贼王”只命中《海贼王女》；1 线路24条目录记录；签发成功，读取媒体发生 `ConnectionResetError` |

旧 `aafun` 与 `moonci` 使用同一主机，迁移需要处理历史别名，不能把它们当作额外第五源。

媒体探测使用 Python 标准库、8 秒请求超时、`Range: bytes=0-4095`，实际最多读取4096字节后关闭；每源独立进程，总预算48秒。没有下载整段视频，没有进行 Web video/Android 原生播放器测试，没有将临时媒体 URL 或签发参数写入文件。

观察到的差异：

- A 首条目录标签是 `174`，目录为倒序；B 首条是 `第01集`。不能把 SDK 返回的第一个元素解释为第1集。
- A 返回 HLS 内容，但 HTTP MIME 是 `image/png @lirose_tv`。必须结合内容、可信格式信息与路径判断媒体格式；仅依赖 MIME 不可靠。
- B 读取到100字节清单，可能还需要继续取子清单；本次未验证子清单、分片和密钥。
- C 将媒体主机登记为需 curl，但本次标准库读取清单成功。SDK 的路由标记不等于所有环境都必须 curl，也不证明 Node/Android 媒体传输已兼容。
- D 的错误只表明本次本机媒体探测失败，不能据此认定整个来源永久不可用。
- D 的搜索结果明确说明“命中非空”不等于“目标作品匹配”；不能将《海贼王女》静默当作《海贼王》播放。

## 4. 业务接入与稳定身份

```text
现有动漫页面 / Bangumi 资料 / 历史收藏 / 弹幕
  → 四份动漫 API 规则 → RuleContentProvider / SourceService
  → SourceRuntimeExecutor
      Web：同源 Node 网关 → Python Runtime
      Android：MethodChannel → Kotlin → Chaquopy Python
  → 共用业务分发 → anifive-a / b / c / d Adapter
  → AniFive SDK

解析结果 → 原有平台播放器 / 下载器
          媒体请求策略单独传递，不会自动继承 SDK 的传输实现
```

应遵循现有[来源接入规范](source-sdk-onboarding.zh.md)的动漫路径。`content_search_playback.dart` 当前显式筛选 `RuleContentProvider`；只增加一个普通 SDK Provider，不会自动进入这条动漫播放链路。

### 三类运行时契约

沿用已存在的固定路径模板，不借用 `adapters/miomedia/sdk`：

| 操作 | 路径 | 适配行为 |
| --- | --- | --- |
| 搜索 | `GET /v1/adapters/anifive-{a,b,c,d}/search?q=...` | SDK 主键映射为可校验的来源详情引用，返回名称及单页状态 |
| 剧集 | `GET /v1/adapters/anifive-{a,b,c,d}/episodes?source=...` | 一次详情读取转换线路与集引用；C 只返回真实 road=2 的可播放记录 |
| 解析 | `POST /v1/adapters/anifive-{a,b,c,d}/resolve` | 校验 `episodeUrl` 所属来源和路径后调用 SDK；只返回媒体地址、必要头、格式与明确的过期信息 |

响应需遵循现有 API 规则映射，例如搜索 `data[].name/url`、目录 `data.roads[].name/episodes[].name/url`、解析 `data.url/headers/format`。具体 envelope 以 `tool/source_runtime/example-rule.json` 为基线建立双端契约测试。

身份处理原则：

1. `providerId`、运行时 Adapter ID、显示名称各司其职。迁移前记录旧 ID；保留可对应的旧身份，或提供显式别名映射，不能随显示名或主机变更重新生成历史身份。
2. A/C/D 使用返回元组中的真实站内 `road/episode`；B 使用完整站内播放路径。站内序号不是必然等于 Bangumi 剧集序号。
3. 集标签、站内引用、列表位置、语义集数分别保存。特别篇、剧场版、上下篇、缺集、倒序、重复标签不能靠列表下标假装唯一集号。
4. 当前 `EpisodeRef` 已区分部分概念，但历史仍使用列表位置，无法解析标签的弹幕集数也会回落下标。复用链路不等于这两处兼容问题自动消失，迁移与回归必须覆盖。
5. 跨来源换源必须匹配同作品、同季和同一集；保留现有唯一匹配策略。SDK 搜索混入“动态漫”等相近名称时不能错误合并作品。

## 5. Web 与 Android 的具体差距

### Web

当前 Dart 和 Node 已允许通用 `search/episodes/resolve` 路径；Python 注册表只有 template 和 Mio，template 没有真实业务能力。需增加四源注册与实际实现，并复用受限网关。

媒体仍由 Web 媒体网关服务：

- HLS 主清单、子清单、分片、密钥及相对路径必须完整通过同源网关；不能只验证解析返回了 URL。
- SDK 对某主机选择 curl，不会改变 Node `https` 的传输栈。先实测 Node；仅对确有失败证据的主机增加受控兼容策略。
- 当前网关通过 MIME 或 `.m3u8` 路径识别清单。A 已出现错误 MIME，必须覆盖错误 MIME、无扩展名等情况，必要时有限读取头部识别。
- 当前跨域重定向会清除可变请求头中的 Cookie/Authorization，但 HLS 子 URL 重写又引用原始 `rawHeaders`。应使用最终允许的请求头，防止被清除的凭据重新进入子请求。
- 保留 Range、取消、超时和单个活动播放器；解析失败应显示该源状态，不切到同名其他作品。

### Android

`android_bridge.py` 当前只支持 health、adapters 和 Mio SDK 分支，并拒绝非空 query。只注册 Python Adapter 会导致新源的 GET 搜索/剧集请求被 Android 拒绝。

需要：

1. 抽取 Web/Android 共用的业务分发及参数校验；允许已登记 Adapter 的有限查询参数，不开放任意脚本/目标 URL。
2. 保留 MethodChannel 请求 ID、提前取消、deadline、并发槽位和响应大小限制。
3. `android/app/build.gradle` 的 `stageEmbeddedPython` 使用显式文件清单；增加 AniFive 包与适配器的必需文件，并检查 APK 的实际内容。
4. 实际 APK 不配置外部 Runtime 地址也能运行四源；电脑上的 Python 进程成功不能替代这一验收。
5. 系统 curl 子进程不是可靠的随包能力。先验证 Android 原生播放器和本地可用 HTTP 传输；确需替代传输时提供可随包、可取消、有大小限制的实现。
6. 如果媒体必须经本地桥转发，桥应单独设计并只绑定 loopback、使用不可猜测会话标识、限定来源/媒体目标；JSON MethodChannel 不用于搬运视频字节。只有实测表明确有必要才增加此模块。

## 6. SDK 需要适配/修复的具体问题

| 级别 | 证据 | 接入要求 |
| --- | --- | --- |
| 必需 | 四个 HOST 均为空 | 建立受维护的主机配置与缺配置状态；开发机临时 override 不是交付配置 |
| 必需 | `_default` 是进程全局；首次 timeout=3 后再传17，实际仍是3 | 改为可注入且会话隔离的传输；每请求读取剩余总预算 |
| 必需 | 限速依赖实例时间戳和 `sleep`，没有互斥；网络与等待不检查 RuntimeContext | 同源限速串行化，不同源可并行；可取消等待，阻塞 IO 有界，避免超时后长期占满工作线程 |
| 必需 | urllib `.read()`、curl 捕获输出没有实际读取大小上限 | 元数据、清单、媒体探测分别设上限；Range 请求被忽略时仍停止读取 |
| 必需 | `IncompleteRead` 有部分数据时直接返回200 | 不把截断响应当作完整成功；按契约有限重试或返回失败 |
| 必需 | `CurlTransport` 命令含 `-k`，无完整响应头和最终 URL | 恢复证书校验；统一重定向、状态、响应头、取消和错误语义；不得依赖取消 TLS 校验解决兼容性 |
| 必需 | C detail 返回多线路，play 固定线路2；只检查解码结果以 `http` 开头 | 只暴露支持线路；拦截外部 HTML 播放页，不将其当媒体成功 |
| 必需 | A 裸媒体请求需要不带来源头；播放器/下载器仍合并规则默认头 | 明确媒体请求头继承/替换策略；`headers: {}` 不等于清除 Referer/Cookie/Origin。按源及媒体目标传递策略，保留平台必要自动头 |
| 必需 | D `expires_at` 文档称建议刷新点；Playra `expiresAt` 表示硬失效 | 核验格式和语义后映射，区分建议刷新与硬过期；失败后受控重新解析 |
| 文档 | `from anifive import build_request_headers` 实测 ImportError | 修正文档导入路径或显式导出，并加示例验证 |
| 文档 | B 无语义集号时建议用列表序号；D 的部分 docstring 与真实参数/元组不一致 | 以源码和真实样本修正契约，不采用会破坏稳定身份的下标兜底 |
| 文档 | 播放文档称非裸媒体 headers 当前也为空；A 实际可返回 UA/Referer | 文档明确按媒体目标决定请求头，不能统一清空或统一继承 |
| 验证 | `e2e_smoke.py` 排除 EMPTY 后执行 `all()`；全空可得到 PASS | 空搜索不能算全链路成功；明确每阶段成功证据 |
| 验证 | C smoke 会在多个搜索结果中换作品；清晰度 kind 未识别也可最终 PASS | 测试固定目标身份；成功至少验证媒体清单/资源，最终以真实播放器为准 |

媒体 URL、面板参数、签发 key、上游 raw 响应不应进入公共接口和日志。站点页面给出的 iframe、播放路径和重定向也需在受维护规则下校验，不能把 Runtime 变成任意网络代理。

SDK 自称零第三方 Python 依赖，不代表零外部运行依赖；系统 curl 是需要单独验证的依赖。

## 7. 16 → 4 的迁移与首页

当前 `copyPluginsToExternalDirectory()` 只补齐缺失的 ID/名称，不替换已有规则、不删除旧规则；正常读取旧 `plugins.json` 也不会自动同步新资产。因此只删旧 JSON、放入四份新 JSON，对现有用户无效。

建议迁移流程：

1. 迁移前备份 `plugins/v2/plugins.json`、来源策略及必要的身份映射，记录迁移版本。
2. 根据已知内置规则指纹/版本识别可迁移项。不能仅凭名称覆盖用户编辑过的规则；无法确认来源的项保留并标注，避免误删自定义数据。
3. 替换可确认的原内置来源集合为四源，继承对应来源开关、顺序、身份；记录 aafun/moonci 别名关系。自定义来源不计入“默认四源”。
4. 四个保留来源的历史旧详情/集路径转换为可校验的新引用；其他退休源保留历史记录和进度，通过同作品、同集重新匹配，而不是假装旧链接已经兼容。
5. 原子提交；失败恢复备份。重复启动不重复添加、不再次重写用户状态。
6. 区分受维护的内置 SDK 规则与普通规则仓库更新。当前按名称匹配的远程更新可能把新包装规则覆盖回旧 XPath；普通自定义规则商店可继续使用，但不能自动覆盖受维护项。

首页需要单独处理：`HomeRuleCatalog` 读取站点目录；`rule_directory_config.dart` 当前主要认识 DM84/7sefun。四份包装规则若都改成虚拟 baseURL 或新名称，来源补充目录会失效。

建议首轮保留 A 的真实来源 baseURL，搜索/选集/解析请求分别指向 Runtime；把已有 A 首页目录规则显式配置到该来源，复用现有目录能力。这样仍只有四个来源，也不会给 SDK 虚报 catalog 能力。Bangumi 负责首页主体和资料；来源目录异常仅影响补充内容。后续若要把首页抓取全部收口到 Python，再增加经过验证的 catalog 契约，不夹带进首轮核心替换。

## 8. 实施顺序与验收

以下为下一阶段方案，尚未实施，也未创建 OpenSpec 变更。

| 顺序 | 工作包 | 完成证据 |
| --- | --- | --- |
| 1 | 固定 SDK 输入版本、主机配置、传输注入和三个业务契约 | 四源 fixture；错误、取消、限速、响应上限测试；不读取外部凭据 |
| 2 | 四个 Adapter 与 Web/Android 共用分发；Android 随包清单 | 两端请求得到同结构、同引用、同错误码；APK 内包含模块 |
| 3 | 四份动漫 API 规则、首页补充、历史身份与迁移 | 新装四源；旧16条迁移；自定义/已编辑规则不丢；迁移重复执行和回滚通过 |
| 4 | 播放器/下载器请求头策略及媒体网关兼容 | 裸头、错误 MIME、HLS 主/子清单/分片/密钥、Range、重定向隔离验证 |
| 5 | Web 与 Android 真机/模拟器完整回归 | 同一目标作品起播、选线、换集、拖动、续播、失败恢复、取消后无晚起播；Android 可用下载功能回归 |

必测动漫边界：A 倒序目录；C 只开放线路2且真实编号不变；B 无法解析集号；剧场版/特别篇；缺集；同名不同季；“海贼王”不能匹配“海贼王女”；旧来源退休后历史可见并正确重匹配。

自动选择优先级可先参考 SDK 的 A/B 主力、C/D 备用，但不要把“最佳”写成无条件全局排名。本次样本不是同一作品/集，耗时不能用于严格性能排名。需要按作品匹配、平台可播放性、近期失败率、实际起播耗时和用户手动锁定综合决策，复用现有来源策略。

相关实现边界：

- Python：`tool/source_runtime/adapters.py`、新增 AniFive 适配/传输模块、`server.py`、`android_bridge.py`、受维护 vendor 输入。
- 平台：`android/app/build.gradle`、必要的 Kotlin 入口校验、`tool/web_backend/runtime.cjs`/`server.cjs`。
- Flutter：`assets/plugins/`、`plugins_controller.dart`、来源身份/解析结果契约、播放及下载请求头消费点、首页来源声明。
- 文档：更新来源接入规范、构建输入和迁移说明；保留 SDK 上游代码与本地兼容修改的边界。

独立 Dart Source API 的既有 `dart:ui` 导入问题应单独记录；若承诺该入口也支持四源，需拆开纯 Dart 传输与 Flutter 内置桥后补集成验证，不应顺便重构整个播放器。

## 9. 本轮验证与交付边界

- DONE：四源需求确认、源码/规范对照、Web/Android 接入路径、迁移与验收方案。
- DONE：9 个不联网模块 selftest，共57个检查通过；固定向量15/15通过。主动跳过含 httpbin 网络访问的 transport selftest，没有把全量 check_all 宣称为离线通过。
- DONE：复现默认 Client 缺配置、文档导出 ImportError、全局传输 timeout 固定在首次值的问题。
- DONE：四源搜索抽样；A/B/C 解析并有限读取 HLS，D 签发成功后媒体探测失败，结果如实保留。
- NEXT：按上述顺序实施并进行双端真实播放验收。若采用 OpenSpec 管理跨模块变更，再按项目约定单独确认是否创建变更材料。

前一轮项目基线验证已有 Python/Node 测试通过，但 Flutter 测试曾在 media_kit 的 VisualStudioResolver/vswhere JSON 解析处、测试开始前失败。本轮没有修改工具链，也没有重跑后宣称该障碍已解除。后续实施须修复或换可验证环境完成 Flutter/平台门禁。

本轮仅新增此分析文档，不修改 Playra 业务代码、不复制 SDK、不替换16条内置规则、不更改外部 SDK 文件。原先未跟踪的 `docs/project-analysis-20261013.md` 保持不动。撤销本轮交付只需移除此新增文档，无业务回滚操作。
