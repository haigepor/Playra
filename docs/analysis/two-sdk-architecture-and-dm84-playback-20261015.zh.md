# AniFive / MioMedia 架构核验与 DM84 播放修复

日期：2026-10-15。基线：`37501c88` 加现有工作区改动；本轮开始时已有大量页面、规则和 SDK 接入改动，本文以当前源码及实测为准。新增接入遵守[统一 SDK 接入规范](../development/source-sdk-onboarding.zh.md)，本文记录架构、故障证据和改进顺序。

## 1. 结论与数量口径

当前封装 **2 套播放 SDK、5 个业务运行适配器**。两者共享运行协议、平台桥和媒体底座，业务身份与选源编排仍是两条路径。后续应复用公共契约，不复制播放器，也不强行把所有来源改成同一种作品身份。

| 项目 | AniFive（动漫） | MioMedia（影视等） |
|---|---|---|
| 私有算法输入 | `vendor/anifive/` | `vendor/miomedia/` |
| 业务 adapterId | `anifive-a/b/c/d` | `miomedia` |
| 展示来源 | DM84、MXdm、akianime、moonci | MioMedia SDK，作品下动态线路 |
| 业务调用 | 每源 search / episodes / resolve | sdk RPC 内 11 个操作 |
| 作品身份 | 真实 Bangumi ID + 规则来源和作品引用 | providerId + contentId，不伪造 Bangumi ID |
| 默认页面 | ModernPlayerDetailPage | SdkDetailPage |
| 内容分类 | anime | Flutter 对外 screen / comicDrama / series |
| 线路 / 画质 | 四站真实线路，未知画质保留未知 | 真实线路码，画质来自实际元数据 |
| 版本收据 | anifive-manifest.json：dc13fdb，集成版本 1 | sdk-manifest.json：original-with-optional-native-bridge-20261013 |

AniFive 是 4 × 3 个具体业务 HTTP 路径；Mio 是 1 个 RPC 路径、11 个操作。运行注册表中的 template 为 implemented=false，不算第 6 个可播放来源；Bangumi 是资料方，不算第 3 套播放 SDK。作品线路数是动态数据，不能从适配器数量推算。

## 2. 动漫完整调用链

```text
动漫搜索 / Bangumi 详情 / 历史入口
 → Plugin + RuleContentProvider
 → SourceCandidates / AnimeSourceSession
 → SourceService / RuleEngine / ApiRuleStrategy
 → SourceRuntimeClient
 → dispatch.py → AniFiveAdapter → AniFive Client / source_a/b/c/d
 → 真实 Road.id + 剧集 URL
 → SourcePlaybackService → VideoController → PlayerPlaybackController
```

`assets/plugins/{DM84,MXdm,akianime,moonci}.json` 是声明层，包含固定运行路由和字段映射，不含签名密钥或解析算法。`anifive_adapter.py` 做模型转换、错误映射和媒体探测；`anifive_transport.py` 负责受限外网请求、限频和预算；供应商私有包执行站点协议。

`SourceCandidates` 用主名和资料确认的别名，最多 4 个关键词、25 秒搜索预算；不能删季号、电影或特别篇标记凑匹配。同名不同引用保持歧义。`AnimeSourceSession.updateWork` 在详情资料补全后更新匹配依据、使旧自动结论失效，保留人工确认并取消迟到请求。

顶层 AniFive 分组通过受管标记与受信任运行路径识别，不靠显示名猜测。四站仍保留独立 providerId、作品引用和真实线路 ID。切线先匹配同集，再提交媒体；缺集不能跳首集。点具体线路进入手动锁定，只有点“自动”才重新允许 SDK 内回退。自定义规则保持独立来源。

## 3. 影视完整调用链

```text
MioContentProvider / 首页目录和榜单
 → MioMediaService / MioSdkPlaybackProvider
 → SdkPlaybackEntry + SdkSourceBinding
 → SdkDetailPage + SdkPlaybackCoordinator
 → SourceRuntimeClient.callMioMedia
 → dispatch.py → MioMediaAdapter → MioMediaSdk
 → 供应商 Client / PlaybackClient
 → SourceMediaPlayer → 原有原生控制器或 Web media_kit
```

`lib/services/source/miomedia/` 承担供应商字段与公共模型转换。公共契约是 SdkPlaybackProvider，核心为详情、目录、播放；可选画质不能默认宣称支持。SdkVideo / SdkLine / SdkEpisode / SdkQuality 保留真实作品 ID、线路码、集号和画质码。

RPC 白名单：recommend、banners、catalog、detail、episodes、qualities、exchange、search、searchConfig、hotRank、play。当前 Mio videoId 要求 1–64 位数字字符串，这是该适配器的约束，不是所有新 SDK 的全局限制。播放响应须核对请求作品、线路与集号，不能接收串集返回。

协调器管理最多 3 路元数据并发、10 秒元数据预算和 75 秒播放回退总预算。内部更小预算仍生效，外层等待更久不会延长一次 Web runtime 请求。目录与画质有页面缓存及在途合并，短时媒体 URL 不作为长期作品身份。自动模式依据实际画质、平台成功记录和耗时排序；手动选择保持锁定，同集切线按真实集号匹配。剪辑时长不同不能盲目续接旧进度。

## 4. Web / Android 公共执行边界

| 阶段 | Web | Android |
|---|---|---|
| 算法入口 | 同源 /api/runtime/v1/... | MethodChannel com.predidit.kazumi/source-runtime |
| 平台桥 | Node runtime.cjs 固定本机目标 | SourceRuntimeBridge.kt + Chaquopy |
| 校验执行 | Python HTTP → dispatch.py | android_bridge.py → 同一个 dispatch.py |
| 媒体网络 | /api/proxy 处理头、跳转、HLS 重写 | 播放器直接请求媒体 URL 和媒体头 |
| 播放所有权 | media_kit 持有 video/HLS，ArtPlayer 仅提供控件 | 原有 mpv/media_kit 配置；明确 HLS 时指定 demuxer |
| 用户数据 | 原有历史、收藏和规则存储 | 原有应用数据，内置算法无需电脑 Python |

Android Python 通过 Gradle 白名单随包，bf_tables.bin 等数据也必须包含。不能打包桌面 DLL、电脑设备身份或整个开发目录。新 SDK 需要同时登记 HTTP 与 Android；Python 注册成功不等于全端接通。

### 4.1 公开接口契约

| 操作 | 契约 | 关键输出与限制 |
|---|---|---|
| AniFive 搜索 | GET /v1/adapters/anifive-{a,b,c,d}/search?q=...&page=1&pageSize=20 | data[] 的 name/url/可选 cover；空结果合法，本地切页不等于上游多页 |
| AniFive 目录 | GET /v1/adapters/{id}/episodes?source=... | data.roads[] 的真实 id/name/episodes；剧集保留 name/url |
| AniFive 解析 | POST /v1/adapters/{id}/resolve，JSON episodeUrl | data.url/format/headers/headerPolicy，可选真实 expiresAt |
| Mio SDK | POST /v1/adapters/miomedia/sdk，JSON operation + payload | 固定 11 操作，各操作字段白名单，不能额外指定 host 或模块 |
| Mio 播放结果 | play 的 videoId/code/episodeNum/可选 quality、caps=[] | ready + media、unavailable + error 或 ad_required；不能只判断 HTTP 200 |
| 诊断 | GET /v1/health、/v1/adapters | 不初始化供应商设备、不换取媒体；健康不证明外站能播 |

运行请求标记 X-Kazumi-Request: 1 与媒体 headers 分属两层，标记不是生产鉴权。Mio 的 exchangeToken 等换取材料不应进入画质按钮模型；不能把 exchange / reward 这类可能消耗状态的操作当普通读请求无限重试。公开响应和日志不得携带设备秘密、完整签名媒体链接或整个上游对象。

### 4.2 会话与并发所有权

AniFive 每个来源由适配器锁管理 SDK 会话；锁等待也检查预算与取消，不能四源共用一套站点 Cookie 状态。MXdm 搜索的限频提示页即使 HTTP 200，也须识别为 RATE_LIMITED；合法空结果继续别名回退。

Mio 使用持久设备身份和有期限的服务会话，播放采用当前明确的 STRATEGY_TOKEN；会话刷新、媒体换取、耗时与结果由适配器持有，页面只处理公开模型。不同 SDK 的设备身份、Cookie、私有缓存不能因为共用运行桥就合并。Node 的 JSON 转发与 HLS 代理是两条请求链：前者成功不代表后者、解码器或播放器所有权正确。

## 5. DM84 为什么匹配成功仍不能播放

必须区分六步：**作品匹配、同集目录、解析、清单读取、分片读取、解码并持续播放**。resolve HTTP 200 只证明第三步。

本轮样本：《航海王》，DM84 公开详情 /v/71.html。两条线路各返回 1180 集，解析都成功；主清单和首个 TS 分片都可读。线路 1 上游 MIME 伪装为图片，实际以 #EXTM3U 开头，分片有合法 TS 同步字节；线路 2 是常规 HLS 并带必要媒体头。因此本次失败不能归因于未匹配，也不需要更换作品引用或切源策略。

### 5.1 清单重写保留旧 Range 元数据

浏览器发送 Range: bytes=0-，上游返回 206 + Content-Range。旧代理重写子资源 URL 后，约 28 万字节清单变成约 35 万字符，仍返回原 206 / Content-Range / Accept-Ranges。这些偏移只适用于原表示，与重写结果不一致。

server.cjs 修复：检测到 HLS 206 且携带 Range 时，关闭旧响应、移除 Range，再获取完整清单后重写；清除旧长度、范围、ETag 和 Last-Modified。上游无 Range 仍返回局部清单则明确失败，避免无限重试或将截断清单当完整结果。MP4 / TS 仍以原 206 流式透传，不整体缓冲。

### 5.2 原生 HLS 探测与实际解码不一致

当前 Chrome 报告 canPlayType(HLS)=maybe，锁定的 media_kit 因此跳过 hls.js。修正网关后正式页面仍报 PipelineStatus::DEMUXER_ERROR_COULD_NOT_PARSE；同清单经 hls.js 对照可解码 1920×1080 并连续出帧。Range 是一个独立缺陷，不能宣称修代理就解决了全部播放问题。

兼容入口 web/player/media_compat.js 由两条播放路径打开媒体前调用。仅在 Chromium 且既有 hls.js 支持 MSE 时，调整当前 media_kit 所属 video 的 HLS MIME 能力探测，让 media_kit 使用其原有 HLS 引擎。不修改全局 DOM 原型、不新建播放器、不接管选集和生命周期。Safari、iOS Chrome、无 MSE 和 MP4 能力探测保留原行为。

这是当前依赖的兼容分支。升级 media_kit 时须核对实例表、_isHLS 判断和资源销毁行为；正式偏好配置可用后应移除此分支。临时注入 HLS 的对照只用于诊断，交付验收必须使用构建后的正式页面。

首次起播须先等待播放器初始化（HLS 脚本包含在内），handle 已存在不代表 HLS 脚本已就绪。续播复测还证实当前 MSE 分支忽略 Media.start；`playback_start_position.dart` 在元数据就绪后补定位，并检查播放器和会话仍为当前选择、进度未越界。它不改变持久化历史、不改变同集选择，Android 保持原起播方式。测试覆盖晚到元数据、退页/切源、超时和越界。

### 5.3 媒体头与平台表示不同

规则解析 headerPolicy=replace 转为 inheritHeaders=false；空字典表示有意裸请求，不能补回站点 Cookie / Referer。Mio 公共播放页直接使用 media.headers，不能假设其自动实现规则解析字段的同一语义。

Web 主清单、子清单、KEY、MAP 和分片经过同源代理；跨主机跳转清除敏感头，子请求不能恢复已清除凭据。Android 直接请求媒体，与 Web 重写表示不同，两端必须独立实播。

## 6. 错误、预算和后续风险

| 边界 | 当前实现 | 新 SDK 要求 |
|---|---|---|
| 运行协议 | 请求 32 KiB、响应 2 MiB；默认 20 秒 | 视频不放 JSON，固定方法和字段 |
| Web runtime 桥 | 最长 20 秒 | 外层 75 秒不能放大内部超时 |
| Python HTTP | 8 个业务执行名额 | 有界并发、取消，禁止无限排队 |
| Android 桥 | 4 工作线程 + 8 排队名额，独立取消线程 | 排队计入预算，晚到响应不覆盖选择 |
| 空结果 | 与限频、超时分开 | RATE_LIMITED / TIMEOUT / CANCELLED / BUSY 不得改为空 |
| 网络 | TLS、跳转、公网目标、大小检查 | 不接受任意 host、脚本或命令 |
| 能力 | Mio caps=[]，当前无 v2ts | 不为更多画质虚报能力 |
| 私有输入 | 两 SDK 各有版本和文件收据 | 算法升级与本地补丁分开，秘密不进附件 |

需要独立跟进的真实问题：

1. **Mio 响应完整性，高优先级**：vendor/miomedia/transport.py 的 parse_wire 计算 hmac_ok，但 decrypt_v3 未先拒绝失败。需要篡改响应回归，核实供应商协议后在正确层失败关闭。本轮不混改私有 SDK 原始协议，这不是 DM84 故障原因。
2. **AniFive 发布输入，发布前必补**：release.yaml 当前仅从 MIOMEDIA_SDK_BUNDLE_1/2 恢复 Mio。AniFive 本机构建不等于干净 CI 能恢复；需独立导入步骤与摘要校验，不能把现有 Mio 秘密名称当成已接通。
3. **播放器依赖兼容，升级时必验**：本轮 HLS 入口依赖当前 media_kit 实例表与选择行为；升级应覆盖 MSE / 原生 HLS、MP4、切线、销毁回归。
4. **媒体探测证明有限**：前 4096 字节成功不能证明全部分片、编码和长时间网络稳定，协议成功与实播必须分别记录。
5. **编排仍分两路**：分组外观统一不等于业务契约完全合并。可逐步抽取一致的同集匹配和状态规则，不建议为形式统一重写动漫历史身份或自定义规则。
6. **无后缀 HLS 的端到端格式提示**：网关已能按内容识别无后缀清单，但当前 media_kit 的 MSE 选择仍检查 URL 是否含 m3u8。新 SDK 返回完全不含该标记的媒体时，需补齐公共格式提示契约和 Web 实播，不能仅凭代理测试就宣称兼容。
7. **既有历史展示与迟到首帧**：本轮观察到倒序目录的“继续观看”标签使用列表下标（1113 显示为 68），但真实 URL 能恢复到 1113。Android 线路 2 一次冷启动超过既有 15 秒首帧预算，随后实际出帧仍保留错误提示。两者属于既有展示/状态边界，需单独修复与回归，不能把本轮线路 1 稳定播放扩大为“所有冷启动异常已修复”。

## 7. 后续 SDK 完整接入切片

1. 选动漫规则或通用 SdkPlaybackProvider 路径，明确真实作品身份、线路、集号和能力。
2. 提供 Adapter、公共模型转换、错误码、预算、取消和脱敏，不向页面公开完整供应商对象。
3. 同步 Dart、Node 白名单、Python dispatch、Android 注册和 Gradle 打包；新 RPC 不冒用 Mio 路由。
4. 覆盖媒体格式/头、HLS Range 重写、子资源、特殊 MIME、MP4 seek 和取消。
5. 验证旧历史、收藏、自定义规则、同集切线、手动锁定和单播放器；不复制整页播放器。
6. 在 Web 正式页面和实际 Android APK 分别记录首帧、持续播放、切线同集和重进恢复；附构建输入、产物摘要、回退位置。

## 8. 本轮验收收据

- Node 后端 36 项通过，包含清单重写 Range、局部清单重取、非预期 206 拒绝、MP4/TS 流式 Range、跳转凭据、取消、运行桥和播放器控件。
- Flutter 相关回归 68 项通过，覆盖原生播放器委托、媒体头、历史身份、冷启动恢复、规则迁移、SDK 分组、手动切线同集、Mio 协调和页面，以及本轮 4 项起播定位回归。
- 定向 analyze 6 个文件无问题；最终 `flutter build web --release --no-pub --no-wasm-dry-run`、`flutter build apk --debug --no-pub` 成功。早期漏导入 dart:async 导致的一次编译失败已修正并重新构建；本节只将最终通过产物作为交付。既有 Wasm FFI 提示和 Gradle/AGP/Kotlin 升级提示不代表本轮 JS Web / debug APK 构建失败，没有声称 Wasm 或商店发布验收。
- 首轮正式 Web 修复包：DM84 /v/71.html、/p/71-1-1180.html，1920×1080，31 秒后退出并保存进度；发现 MSE 忽略 Media.start 后继续修复，不能把此轮重进误记为续播成功。
- 安卓：雷电 emulator-5554，包 com.predidit.kazumi；两条 DM84 线路均播放第 1113 集，线路 1 超过 5 分钟，线路 2 超过 1:48。覆盖安装后从原历史恢复到第 1113 集；线路 1 再次播放到 0:48，无错误提示。线路 2 冷启动异常另见第 6 节。
- 最终 Web 正式包：从既有 7:12 进度恢复 `/p/71-1-1180.html`，随后观察到 7:31 → 8:13.714，1920×1080，帧数 537 → 1567，readyState=4、无媒体错误；只有一个 video，未做控制台播放器替换。
- 最终 APK 再次保留数据覆盖安装成功，从 6:06 恢复第 1113 集，随后观察到 6:20 → 8:33，DM84 / 线路 1，无错误提示。电脑 Python 不承担 APK 的媒体解析，APK 走内置桥。
- 验证 Web 服务为 `http://127.0.0.1:18932/`，本轮仅重启这一隔离服务，未重启 18930/18931 的既有服务。正式运行环境更新后仍需重启 Node 并刷新页面才能使用新代码。
- 最终产物：`build/web/main.dart.js` SHA256 `9275E178AA68B31506A6241FC66B3CDF05A44D878AFDEB5A2DB78C21116B350C`；`build/app/outputs/flutter-apk/app-debug.apk` SHA256 `064C2E78E6AF589FFE597995BCE83656C5E2EB6A95FFADF0F4CDA1C43317AF9B`，后者已安装雷电。debug 包不是商店签名发布包。
- 证据目录 `.dart_tool/dm84-playback-20261015/`：Web/安卓截图、UI XML 与本轮前快照；不附完整签名 URL、Cookie 或设备身份。Mio 本轮完成源码和公共回归核验，没有重做全站逐线路实播，不把此前文档的实播算作本轮结果。

结论：本轮 DM84 主故障修复与两端线路 1 实播、同集历史恢复 PASS；全来源/全部冷启动和发布就绪不能标全量 PASS，第 6 节列出可复现边界与后续项。历史、收藏和自定义规则未清空；迁移与身份保持由相关回归验证，不宣称人工穷举了用户全部收藏和自定义站点。

## 9. 修改范围与回退

业务修改限于媒体代理 Range、Web HLS 兼容和起播定位、回归和文档；未修改匹配、自动范围、手动锁定、集号、历史收藏存储或迁移逻辑。

| 文件 | 本轮目的与影响 |
|---|---|
| tool/web_backend/server.cjs | HLS 重写的完整响应语义；二进制 Range 保持原行为 |
| tool/web_backend/hls_relay.test.cjs | 清单 Range 与二进制流式回归 |
| web/player/media_compat.js、web/index.html | Chromium HLS 兼容入口和随 Web 加载 |
| tool/web_backend/media_compat.test.cjs | Chromium / Safari / 无 MSE / MP4 / 重复配置边界 |
| lib/services/platform/media_resource_web.dart、media_resource_native.dart | 平台化播放器配置；原生为空操作 |
| lib/pages/player/controller/player_playback_controller.dart | 动漫打开前配置、Web 起播定位和迟到检查 |
| lib/services/player/source_media_player.dart | 通用 SDK 打开前复用同一配置入口 |
| lib/services/player/playback_start_position.dart、test/playback_start_position_test.dart | Web 媒体就绪后的历史定位及回归 |
| 本文、docs/analysis/README.md | 两套 SDK 现状、证据、风险与导航 |
| docs/development/source-sdk-onboarding.zh.md、templates/source-sdk-checklist.zh.md | 规范 v1.4 与新 SDK 媒体验收门禁 |

本轮前快照位于 `.dart_tool/dm84-playback-20261015/before/`，保持原相对路径。回退时逐文件恢复快照、移除本轮新增兼容脚本/定位辅助/对应测试和本文、重建 Web/APK 并重启验证服务；不得 git reset 覆盖工作区原有页面和接入改动，不清空应用数据。
