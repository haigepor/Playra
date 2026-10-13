# 规则服务完成度与 Python 影视接口接入审查

日期：2026-10-12。项目：`C:\Users\haige\Desktop\Playra`。

## 结论与本轮范围

统一规则服务和本机 HTTP 外观层已实现；现阶段不能认定影视数据、页面与 Python 算法已经接通。Python 应优先作为独立 HTTP 适配服务运行，由现有 JSON API 规则调用。需要本机离线算法时，再单独评估跨平台解释器或 Dart 算法移植。

本轮是 L 级跨模块研究：核查代码、OpenSpec、实际服务和官方平台文档，形成设计建议。只新增本文件，不修改应用、规则、依赖、打包或全局配置，不创建新的 OpenSpec 变更。未安装 Python、执行外部算法或部署影视服务。

## 当前能力：实现、运行和验收分开判断

| 能力 | 当前结论 | 依据与限制 |
|---|---|---|
| 来源身份、能力、上下文与旧 JSON 兼容 | 已实现 | `SourceDefinition`、`SourceManifest`、`SourceContext`、`Plugin` 兼容入口；能力声明不等于站点实测可用 |
| XPath / JSON API 搜索、剧集 | 已统一 | `Plugin` 委托 `SourceService`，复用 `RuleEngine`；并非新旧两套解析器 |
| 来源领域 | 已实现基础划分 | `anime` / `screen` 与规则技术方式分开；16 条内置规则全部为 anime |
| 分类目录 | 动漫范围已实现 | `SourceDirectoryRegistry` 固定返回全部、国漫、日漫、动漫电影，条目 kind 固定为 anime；不是通用影视目录 |
| 分页 | 已实现，但有能力边界 | 默认 local；真实上游分页须声明 searchPagination，并在 API 请求使用 @page；未实现任意站点下一页推断 |
| 解析、验证码、取消 | 已有共享边界 | 保留原生 WebView；HTTP 使用浏览器网关；resolveApi 支持 HTTP JSON 返回媒体地址，不执行 Python |
| HTTP API | 已实现，可独立启动 | 来源、搜索、线路、解析任务、验证任务、媒体转发与健康查询；仅 loopback 服务，未提供公网部署鉴权 |
| 操作健康 | 已实现基础记录 | search/catalog/episodes/resolve 的最近状态；主要保存在当前进程/会话，不是持久化全站监控 |
| 自动优选与恢复 | 部分完善 | 已有性能记录、有限回退、取消和手动优先；仍有集数身份、状态误判、恢复等待等问题 |
| 影视首页、详情和播放闭环 | 未完成 | 推荐/热门影视频道当前明确为空；首页加载器及自动选源仍依赖 BangumiItem |
| Python 执行层 | 未实现 | 项目业务目录未发现 .py、pyproject 或 Python 运行器；现有 Process 调用用于更新器打开文件等功能 |

`unify-source-services-http-api` 与 `classify-and-schedule-playback-sources` 的 tasks 均已勾选，但第二个变更仍标明原生真实播放待手动验收。勾选不能覆盖之后发现的边界问题。两个变更仍在 `openspec/changes/`，本轮不归档它们。

### 当前实际链路

```text
应用新旧页面 → Plugin / SourceService → RuleEngine
                                     ├─ XPath HTML
                                     └─ JSON API
播放 → SourcePlaybackService → resolveApi / 直链 / 原有 WebView

外部调用 → SourceHttpServer（Dart）→ 同一 SourceService / RuleEngine
                               → SourceGateway → Node 请求/浏览器网关
Web /api/v1/* → Node 同源转发 → 本机 SourceHttpServer
```

`SourceHttpClient` 已有客户端实现，但当前应用仍默认直接调用内部服务；其显式构造调用见 HTTP 集成脚本。新增 HTTP API 不代表 Android 必须经过电脑上的 Node/Dart 服务。

## 现场检查记录

| 检查 | 实际结果 |
|---|---|
| 8933 `/api/health` | HTTP 200，status=ok；只证明 Node 网关运行 |
| 8933 `/api/v1/health` | HTTP 502；默认转发的来源服务未启动 |
| 8940 `/api/v1/health` 与 `/sources` | 连接被拒绝 |
| 临时来源服务 8941 | 实际启动成功；health 返回 apiVersion=1、sources=16 |
| 临时 `/sources` | 16 条全部 domains=[anime]；7sefun、DM84 声明 catalog/categories，其余未声明目录 |
| 现有 HTTP 集成脚本 | PASS: 32 HTTP integration checks；真实 Dart RuleEngine + 本机网关 fixture |
| 临时服务清理 | Ctrl+C 停止后，无 8941 监听；不改变默认服务状态 |

实际执行：

```powershell
.\.tooling\flutter\bin\cache\dart-sdk\bin\dart.exe --packages=.dart_tool/package_config.json tool/source_api.dart --port 8941 --gateway http://127.0.0.1:8933
.\.tooling\flutter\bin\cache\dart-sdk\bin\dart.exe --packages=.dart_tool/package_config.json tool/source_api_integration.dart
```

fixture 覆盖分页、部分失败、上下文隔离、解析/取消、验证与媒体/HLS 等接口行为。它不证明 16 个真实站点全部可播放，也没有验证任何 Python 加解密算法或影视服务。历史官方规则对照记录见 `docs/verification/official-anime-rules-audit.zh.md`，本轮未重新请求全部官方配置或逐站播放。

## 影视扩展前应补齐的边界

1. **条目分类必须来自真实数据。** SourceService.search 目前按规则整体 type 为所有结果赋值。只提供电影的规则可用 type=movie；混合影视接口不能全部写 movie。需要逐条映射 kind、年份、季、地区、格式与分类证据。技术适配方式 http 不等于内容领域 screen。
2. **增加 JSON 目录适配器。** 现有目录实现抓 HTML 首页、识别动漫导航，不会因 searchMode=api 或 resolveApi 配置自动读取影视目录。影视 categories/catalog/detail 要有独立契约和能力声明；首页各频道按需分页、增量渲染。
3. **接通通用作品身份。** HTTP 已有 providerId 和不透明 SourceRef，但首页 HomeFeedLoader、播放候选和 OnlineVideoPlaybackArgs 仍使用 BangumiItem。应增加通用作品上下文，保留 anime 的 Bangumi 映射；不得把影视外部 ID 伪造成 Bangumi ID。评论、收藏和历史也要明确元数据来源与身份。
4. **电影正片与电视剧集数分别处理。** “正片”、SP、上下部、不同季不能只用列表位置跨源匹配。影视接口应保留真实 content/season/episode ID、集号证据及线路内索引。当前电影正片不能假定能套用整数集数自动换源逻辑。
5. **能力声明应可核验。** 当前 manifest 基础能力统一声明 search/episodes/resolve，目录能力按配置判断；无配置的能力和真实健康状态应区分。HTTP 内容详情目前是已取得的引用数据，不是任意站点完整详情抓取器。

### 当前已定位、尚未修复的问题

- **P1 集数身份：** 官方补写的“第N集”来自列表位置，当前匹配无法区分它和真实集号；自动跨源可能错集。
- **P1 无资源判断：** 非精确标题被过滤后的空候选可能标为 noResult，导致有相关搜索结果的来源被隐藏；需要 unmatched/needs_confirmation。
- **P1 扩展更新：** PluginsController._replacePlugin 保留 sourceId，但直接替换对象，官方更新可能丢失本地 sourceConfig.resolveApi 等配置。自定义影视规则宜使用独立 sourceId，长期将本地扩展与官方字段分开管理。
- **P2 缓存：** 当前候选键含作品 ID、providerId、版本、src，没有执行配置指纹或验证会话代次；同版本修改算法服务、模板或 Cookie 后可能使用旧目录。
- **P2 调度：** recover 的补检索仍可能等待所有来源；discover 吞掉单源错误。应增量恢复并区分空结果、超时、验证码和不确定匹配。
- **P2 性能：** 当前平均成功耗时与失败惩罚不能保证此刻最快；应记录解析、首帧、算法版本与执行环境，增加同域名配额。不要同时启动 16 个播放器测速。

## Python 应放在哪里运行

| 路径 | Windows | Android | Web | 判断 |
|---|---|---|---|---|
| 独立 Python HTTPS 服务 | 可调用 | 可调用 | 经当前网关调用或专门同源转发 | 推荐作为第一阶段；需实际可达部署 |
| Windows 本地 Python 常驻服务 | 可实现 | 手机不能调用自己的 localhost 来访问电脑 | 当前通用网关拒绝本地目标，须专门固定转发 | 适合开发/桌面，不能直接解决三端 |
| 每次请求启动 python.exe | 可实现进程桥接 | 当前 APK 无解释器，不能照搬 | 浏览器不能通过 Dart Process 启动本机程序 | 不建议作为高频解析默认方式 |
| APK 内嵌 Python | 另需桌面方案 | 可另行集成解释器、标准库、依赖和 JNI/桥接 | 不能沿用这套原生嵌入机制 | 包体、ABI、依赖及生命周期都要验证 |
| 将固定算法移植 Dart | 可用统一实现 | 可用统一实现 | 可用统一实现，须支持 Web 的依赖 | 简单稳定算法可选；需逐字节一致性测试 |

依据：CPython 官方说明 Android 使用嵌入解释器的应用模式，需要打包解释器、标准库和代码；标准 subprocess 不支持 Android/iOS/WASI。Dart 官方说明浏览器不能使用 dart:io，包括 Process。Windows 调用 Python 仍需提供明确的解释器路径和依赖，本项目尚未提供这些桥接。[Python Android](https://docs.python.org/3.14/using/android.html)、[Python subprocess](https://docs.python.org/3.14/library/subprocess.html)、[Dart dart:io](https://api.dart.dev/dart-io/)、[Dart Process.start](https://api.dart.dev/dart-io/Process/start.html)。

这里核对的是平台边界，未为未来服务选择或安装 Python 版本、Web 框架、加密库。若需要完整本机运行，应单独设计跨平台 Runtime 接口，不把 Windows 的命令调用混入共享 RuleEngine。

## 推荐接入方案：Python HTTP 适配服务

```text
Flutter 页面
   ↓
SourceService / RuleEngine（保持原动漫逻辑）
   ↓ searchApiConfig / chapterApiConfig / sourceConfig.resolveApi
自定义影视 HTTP 适配服务
   ├─ 规范化参数、会话、时间戳与编码
   ├─ Python 签名或请求加密
   ├─ 请求上游接口
   ├─ Python 响应解密与数据校验
   └─ 返回标准搜索、线路、剧集或媒体对象
```

注意区分两种 HTTP API：本项目 `/api/v1` 是对调用方暴露规则服务；自定义 Python 服务是被规则调用的上游适配器。后者不必重写本项目全部会话、媒体和任务接口，也不能直接把前者的 DTO 当成已经支持导入的规则。

若上游搜索、详情和解析都要签名/解密，三者都要经过 Python 服务。只增加 resolveApi 只能解决最终媒体解析，不能修复加密搜索或剧集请求。算法需根据目标协议确定，不能先猜 AES、RSA、MD5 的组合。

### 可复用的配置片段

以下是**配置片段**，需合入现有完整兼容规则 JSON；占位域名并未部署，不能直接播放。例子是只提供电影的来源；混合影视仍需上述逐条分类扩展。

```json
{
  "sourceId": "custom-film-api-v1",
  "name": "自定义电影接口",
  "api": "8",
  "type": "movie",
  "version": "1.0.0",
  "baseURL": "https://adapter.example.com",
  "searchMode": "api",
  "chapterMode": "api",
  "searchApiConfig": {
    "request": {
      "method": "GET",
      "url": "https://adapter.example.com/v1/search",
      "query": {"q": "@keyword", "page": "@page", "pageSize": "@pageSize"}
    },
    "listPath": "$.data[*]",
    "namePath": "$.title",
    "sourcePath": "$.detailUrl"
  },
  "chapterApiConfig": {
    "request": {
      "method": "GET",
      "url": "https://adapter.example.com/v1/episodes",
      "query": {"source": "@source"}
    },
    "format": "nested",
    "roadsPath": "$.data.roads[*]",
    "roadNamePath": "$.name",
    "episodesPath": "$.episodes[*]",
    "episodeNamePath": "$.name",
    "episodeUrlPath": "$.url"
  },
  "sourceConfig": {
    "domains": ["screen"],
    "searchPagination": {
      "enabled": true,
      "totalPath": "$.total",
      "hasMorePath": "$.hasMore"
    },
    "resolveApi": {
      "request": {
        "method": "POST",
        "url": "https://adapter.example.com/v1/resolve",
        "bodyType": "json",
        "body": {"episodeUrl": "@episodeUrl"}
      },
      "urlPath": "$.data.url",
      "headersPath": "$.data.headers",
      "formatPath": "$.data.format",
      "expiresAtPath": "$.data.expiresAt"
    }
  }
}
```

章节请求使用固定 `/v1/episodes` URL 加 query.source=`@source`，由服务识别自己的引用。不要把完整 URL 的变量直接作为 request.url：当前 URL 模板会编码替换值。Python 返回的 detailUrl/episode URL 建议是自己服务的可验证引用，不让请求任意转发用户提供的 URL。

`resolveApi` 当前运行变量只有 episodeUrl 与兼容的 source，不包含算法名、时间戳、用户身份、密钥或完整 SourceContext。时间戳、nonce、签名、会话令牌的生成应在 Python 服务内部完成。需要按登录用户隔离时，应增加经过审查的鉴权/会话适配，不能把现有内部 sessionId 当成自动传给 Python 的身份。

Python 解析响应应返回：

```json
{
  "data": {
    "url": "https://media.example.com/video/master.m3u8",
    "headers": {"Referer": "https://source.example.com/"},
    "format": "hls",
    "expiresAt": "2026-10-12T12:00:00Z"
  }
}
```

日期仅示意，实际必须晚于当前时间。当前媒体解析只接受有效 HTTP(S) 地址；format 识别 hls 或按扩展名判断，其他值回到 auto，不能假定任意格式枚举已支持。算法进程日志与 API JSON 分开输出，密钥留在服务端，不进入可导出的规则 JSON。

## 部署与执行细节

### 本地开发与三端访问

- 当前 Node 网关 `security.cjs.validateTarget` 拒绝 localhost、私网 IP 和非 80/443 端口。因此 Web 规则指向 `http://127.0.0.1:8000` 会被拦截；来源 HTTP 服务也经同类网关访问规则目标。
- 本地 Python 调试应添加专门的固定路由转发，只连配置好的 Python 地址，并有受限方法、请求体、超时及取消机制；不放开通用代理的全部内网访问。当前 `/api/v1` 只固定转发 Dart 来源服务，并不会自动转发 Python。
- 正式三端服务宜使用可达的 HTTPS 域名。Android 中 127.0.0.1 是手机自身；仅在电脑启动 Python 不会使 APK 自动获得它。局域网开发需要明确地址/绑定/TLS或开发配置，不覆盖现有公网代理策略。
- 浏览器媒体播放还涉及 CORS、Range、HLS 分片和密钥请求；不要仅用“解析 JSON 返回成功”作为可播放验收。当前外部 HTTP 媒体引用转发与应用默认本地执行路径分别验证。

### 算法与性能

1. 提取协议真实输入：参数顺序、JSON 序列化、字符编码、大小写、时间戳单位、nonce、key/IV、签名位置、响应压缩/编码与解密顺序。
2. 将脚本入口整理成稳定函数，如 sign_request / decode_response / resolve_media；网络适配层负责超时、会话和错误。算法层可先用固定向量离线核验。
3. 默认常驻服务，复用受控连接池；不要每次点击或播放分片都重新启动 Python。少量 CPU 算法与上游耗时分别计时。
4. 若算法确实需要进程隔离，采用固定解释器、固定脚本、参数数组或 stdin JSON、明确工作目录、UTF-8 与输出大小限制。Windows 桥接使用 Process.start，持续消费 stdout/stderr，并处理超时后的进程清理；不使用用户提供的命令字符串或任意脚本路径。此桥接尚未实现。
5. 外部服务用服务器控制的 adapterId/算法版本，不提供开放 eval、exec、任意导入或任意 URL 转发端点。隔离范围取决于服务是否只运行维护者脚本，不能把 Python 子解释器等同于安全沙箱。
6. 缓存绑定 providerId、有效配置/算法版本、作品剧集身份和会话；短期媒体 URL 按 expiresAt 使用，过期重新解析。不要让一人的 Cookie 与签名结果被另一人复用。
7. 若上游媒体地址与出口 IP、Cookie 或 UA 绑定，Python 服务器解析后客户端直连可能失败；需保持媒体访问上下文，必要时经过受限媒体转发。解析与媒体请求必须作为一条链路验收。

### 错误与重试

规划区分 NO_RESOURCE、UNMATCHED、AUTH_REQUIRED、CHALLENGE_REQUIRED、TIMEOUT、UPSTREAM_ERROR、DECRYPT_ERROR 与 EXPIRED。当前 HTTP/RuleEngine 不会自动保留 Python 返回的任意业务错误码，需要在适配层补映射并保留安全信息。

解密失败不隐藏为“没有资源”，也不反复重试同一个坏密文；签名时间偏差或 token 过期只在协议允许时有限刷新。切集/换源时取消旧请求并禁止旧结果回写，Python 的请求上下文和任务预算也要跟随失效。

## 建议实施顺序与验收

1. **先修规则边界：** 集数身份、unmatched、更新保留扩展、配置/验证缓存失效；保留官方 16 条规则核心行为。
2. **接入一个自定义影视服务：** 明确目标站点、合法可用的凭据/协议、实际 Python 脚本及部署位置；以一个来源跑通搜索→详情→线路→剧集→解析→媒体首帧。
3. **通用影视目录与作品上下文：** 每条内容分类、电影正片/电视剧季集、资料映射、影视详情、历史收藏；首页按频道懒加载和分页，不再聚合完所有数据才渲染。
4. **扩展算法执行契约：** 优先服务端 Python。只有本机运行确为需求时才做 Windows 进程桥接、Android 嵌入或 Dart 移植，并分别验收。
5. **运营能力：** 鉴权、会话、算法版本、耗时指标、错误分类、按来源/域名限流及短期媒体转发。不要直接把现有本机 API 绑定到公网宣称部署完成。

验收至少覆盖：真实分页和分类、电影正片/多季/缺集、标题不确定与无资源区分、签名固定向量、解密失败、超时取消、媒体过期与出口绑定、手动优先与自动有限回退、登录会话隔离、Android/Windows/Web 的实际首帧。

## 源码索引与交付

| 文件 | 责任 |
|---|---|
| `lib/services/source/source_service.dart` | 来源定义、统一搜索/剧集、resolveApi 与健康 |
| `lib/plugins/plugins.dart` | 旧规则 JSON 及新旧业务调用兼容 |
| `lib/services/source/source_profile.dart` | 内容领域与适配方式 |
| `lib/services/source/source_directory.dart` | 当前动漫目录实现与分类 |
| `lib/services/source/source_resolve_config.dart` | HTTP 请求与媒体 JSON 映射 |
| `lib/services/source/source_playback_service.dart` | 应用 HTTP/直链/WebView 解析边界 |
| `lib/services/source/source_candidates.dart` | 当前 Bangumi 作品候选、集数匹配与缓存 |
| `lib/services/source/source_http_server.dart` | 本机 API、会话、任务及媒体引用 |
| `lib/services/source/source_http_client.dart` | HTTP 调用方客户端 |
| `tool/source_api.dart` | 独立 Dart 来源服务启动入口 |
| `tool/web_backend/server.cjs`、`security.cjs` | Web 同源转发、请求网关与地址边界 |
| `lib/presentation/modern/home/modern_home_controller.dart` | 当前首页 Bangumi 加载和影视空频道 |
| `lib/plugins/plugins_controller.dart` | 规则更新及本地扩展保留缺口 |

**DONE：** 完成度核查、实际接口探测、32 项集成检查、跨平台文档核对与接入建议。

**NEXT：** 获取一个目标影视接口的协议/脚本，按上述顺序另行形成可实施契约；本轮没有承诺或启动实现。

修改文件仅本报告，用途为审查与接入设计，无应用运行影响；回滚只需移除此新增报告，原有工作区变更保留。
