# 统一内容源与 HTTP API

应用内部使用 `SourceService`，HTTP 服务复用同一 `RuleEngine`，XPath 和 JSON API 不重复实现。来源能力按规则声明，目录另由适配器注册；缺失能力返回 `UNSUPPORTED`。

## 启动

在项目根目录执行，先启动现有浏览器后端，再启动来源 API：

```powershell
$env:KAZUMI_WEB_PORT = '8933'
$env:KAZUMI_WEB_ROOT = (Join-Path $PWD 'build/modern-home-preview')
node tool/web_backend/server.cjs
```

另一个终端执行：

```powershell
dart --packages=.dart_tool/package_config.json tool/source_api.dart --port 8940 --gateway http://127.0.0.1:8933
```

需要载入规则商店当前全部配置时，加 `--catalog`；载入独立规则对象或数组时，加 `--rules C:\path\rules.json`。这些选项不写应用用户的安装目录。商店与内置同身份时后载入配置覆盖，仍使用同一规则服务。

直接 VM 入口避免 `dart run` 对整个 Flutter 依赖树运行无关的原生构建钩子。首次使用先 `flutter pub get`，不升级依赖。

服务默认只监听 `127.0.0.1:8940`；Web 后端 `/api/v1/*` 固定转发到该端口。不同端口通过 `KAZUMI_SOURCE_API_PORT` 配置；不会将该变量用于任意转发地址。

## 调用

```powershell
$root = 'http://127.0.0.1:8940/api/v1'
$session = Invoke-RestMethod -Method Post -Uri "$root/sessions"
$headers = @{ 'X-Kazumi-Session' = $session.id }
Invoke-RestMethod -Uri "$root/sources"
$result = Invoke-RestMethod -Headers $headers -Uri "$root/sources/dm84/search?q=CLANNAD&page=1&pageSize=20"
$contentId = $result.data[0].id
$lines = Invoke-RestMethod -Headers $headers -Uri "$root/sources/dm84/contents/$contentId/lines"
```

Web 使用同源 `http://127.0.0.1:8933/api/v1`。Dart 调用方使用 `SourceHttpClient('http://127.0.0.1:8933')`，构造参数是站点根地址，不包含 `/api/v1`；客户端负责创建会话、携带会话头、取消及结构化错误。现有应用仍默认本地执行，HTTP 已可供其他调用方使用。

## 路由

| 方法 | 路径（省略 /api/v1） | 返回 |
|---|---|---|
| GET | /health | 服务状态与来源数 |
| POST | /sessions | id、空闲过期秒数 |
| GET | /sources、/sources/{id} | 来源身份、规则版本、协议级别、来源与能力 |
| GET | /sources/{id}/health | 当前会话内 search/catalog/episodes/resolve 各操作的检测记录 |
| GET | /sources/{id}/categories | 来源可支持的目录分类 |
| GET | /sources/{id}/contents?category=all&page=1&pageSize=20 | 分类目录与分页 |
| GET | /sources/{id}/search?q=...&page=1&pageSize=20 | 单来源搜索与分页 |
| GET | /search?q=...&page=1&pageSize=20 | 聚合结果，各来源独立成功/错误和分页 |
| GET | /sources/{id}/contents/{contentId} | 搜索或目录获得的条目，detailMode=reference |
| GET | /sources/{id}/contents/{contentId}/lines | 线路与剧集对象 |
| POST | /playback/resolutions | 创建解析任务，202 |
| GET、DELETE | /playback/resolutions/{jobId} | 查询、取消解析 |
| POST | /challenges | 创建规则已配置的验证任务，202 |
| GET、DELETE | /challenges/{jobId} | 轮询、取消验证 |
| POST | /challenges/{jobId}/submissions | 提交验证码 |
| GET、HEAD | /media/{opaqueToken} | 带服务端播放上下文的媒体流 |

创建解析的 JSON：`providerId`、`contentId`、`lineId`、`episodeId`，全部来自先前查询。创建验证的 JSON：`providerId`、`keyword`；提交验证的 JSON：`code`。不接受客户端自定义上游 URL、XPath 或脚本。

任务状态为 `pending / ready / challenge_required / failed / cancelled`。解析 ready 的 result 包含 `url`、`format`、`expiresAt`。验证 ready 表示已保存该会话的 Cookie/UA，调用方重新执行原搜索；原生应用继续保留原来的验证码完成后结果页复用流程。API 规则当前不支持网页验证码流程。

## 数据契约与边界

- 来源 ID：优先可选 `sourceId`；旧规则按大小写归一名称生成兼容 ID。安装/更新时持久化身份，更新保留原 ID。旧 JSON 字段和非活动 API 配置继续兼容。
- 搜索/目录内容：`providerId, id, title, coverUrl, classification, sourceUpdatedAt, broadcastAt`。缺失字段为 null，类型未判定为 unknown。来源条目 ID 不等于 Bangumi ID。
- 分类：`kind, region, format, rawCategory, evidence`。现有目录适配器支持全部/国漫/日漫/动漫电影；其他来源未配置目录时不能编造列表。详情目前提供已取得的引用数据，未擅自宣称提供完整站点剧情或元数据。
- 线路：`id, name, episodes`；剧集：`id, title, index`。实际请求入口保留在服务端，不把 SP/OVA 等名称强制转为整数集数。
- 分页：`page, pageSize, mode, total, hasMore`。local 的 total/hasMore 仅指本次已抓取集合。upstream 必须由规则显式配置，未知总量/下一页为 null。
- 真实上游分页扩展：在 `sourceConfig.searchPagination` 中配置 `enabled: true`、可选 `totalPath`/`hasMorePath`；API request 的 URL/query/body 使用 `@page`、`@pageSize`。现有固定第一页规则保持 local，不自动推断下一页。
- 健康：操作、状态、checkedAt、elapsedMs、errorCode。搜索空结果是成功；取消不记录故障；目录收录或搜索成功不能证明播放成功。
- 错误统一为 `{ "error": { "code": "...", "message": "...", "providerId": "..." } }`。参数错误 400，会话缺失 401，引用不存在 404，验证码需要 409，请求过大 413，不支持能力 422，繁忙 429，上游失败 502，超时 504。
- 会话空闲 30 分钟过期；内容引用最多 2000 项，任务最多 8 项并在 2 分钟后过期；规则搜索聚合并发 4。HTTP 请求并发上限 12、JSON 请求体上限 32 KiB。
- 媒体引用是持有即授权的不透明短期令牌，2 小时过期。Cookie 和鉴权头保留服务端，HLS 清单/分片/密钥通过同类媒体引用转发；跨主机子资源不继承 Cookie/Authorization。上游视频仍可能更早过期，需要重新解析。
- 浏览器解析/验证需要现有 Node 后端和 Chromium；Android/Windows 应用继续使用各自 WebView，无需 Node。独立接口只服务本机，没有公开部署或远程鉴权配置。

## 验证与回滚

```powershell
dart --packages=.dart_tool/package_config.json tool/source_api_integration.dart
flutter test --no-pub test/source_service_test.dart test/rule_engine_test.dart test/plugin_api_config_test.dart test/plugin_import_parser_test.dart
node --test tool/web_backend/parser.test.cjs
openspec validate unify-source-services-http-api --type change --strict --json
```

HTTP 集成使用本机网关 fixture 和实际 RuleEngine，不依赖第三方站点可用性。平台实机播放与验证码需另外验证，不能由这些测试推断。

迁移保留 `Plugin` 与 `HomeRuleCatalog` 兼容入口。回滚时停用来源 HTTP 服务、撤回这两个入口及解析包装的委托即可，用户规则、收藏、历史没有删除或强制迁移。
