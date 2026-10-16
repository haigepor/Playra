# 当前接口接入清单

日期：2026-10-13。根据当前工作区的实际代码核对；“已接入”表示有调用实现，不等于所有服务今天在线，也不等于所有端点已实测。

2026-10-16勘误：Mio模块未提供可确认的七天统计窗口，本文原“七天榜单”更正为来源热播榜。新增Lumina及双SDK“热播推荐”见[SDK接入规范](../development/source-sdk-onboarding.zh.md)，本清单其余条目仍为原日期快照。

## 总体结构

当前业务由两条内容链路和若干辅助服务组成：

- Bangumi：番剧元数据、榜单、日历、评论、角色与工作人员，以及基于 Access Token 的收藏同步。
- MioMedia：来源作品目录、分类发现、热搜、搜索、来源热播榜、线路、剧集与播放材料。来源作品保持独立字符串 ID。
- 弹弹play：弹幕与弹幕作品/剧集匹配。
- 规则源：网页或 JSON API 搜索、线路/剧集提取和 WebView 视频解析。
- 辅助服务：trace.moe 以图搜番、GitHub 发布更新、规则仓库、WebDAV 同步、Syncplay 同播。
- 本地桥接：Web Node 网关、Dart 来源 HTTP API、Python SDK Runtime，以及 Android MethodChannel/Chaquopy。它们不是额外的影视内容供应商。

## 1. MioMedia：11 个运行层操作

代码：`tool/source_runtime/miomedia_adapter.py` 的 `OPERATIONS`；页面入口为 `lib/services/source/miomedia/miomedia_service.dart`。

原始 SDK 默认基址为 `http://1.14.219.101:7090`，API 前缀为 `/api/v1/app/client`。服务端可用 `PLAYRA_MIOMEDIA_BASE_URL` 覆盖基址；下表路径均相对此前缀，不包含密钥或设备身份材料。

| 运行层 operation | 上游 POST 路径 | 用途 | 当前接入层级 |
| --- | --- | --- | --- |
| `recommend` | `/home/recommend` | 推荐作品 | 运行层开放；当前新版首页没有直接调用该 operation |
| `banners` | `/banner/list` | 轮播作品 | 运行层开放；当前新版首页没有直接调用该 operation |
| `catalog` | `/video/categoryList` | 目录、分类和分页列表 | 新版首页、分类页使用 |
| `detail` | `/video/detail` | 标题、简介、封面和线路 | MioMedia 详情页使用 |
| `episodes` | `/resolve/episodes` | 按作品及线路取真实剧集编号 | 详情页/选集使用 |
| `qualities` | `/resolve/qualities` | 清晰度与 exchangeToken | 运行层开放，同时被 `play` 内部使用 |
| `exchange` | `/resolve/exchange` | 换取播放材料 | 运行层开放，同时被 `play` 内部使用 |
| `search` | `/video/search` | 关键词检索、分类发现兜底 | 搜索页、分类发现使用 |
| `searchConfig` | `/video/searchConfig` | 热搜条目与作品分类线索 | 新版首页发现流程使用 |
| `hotRank` | `/video/modules` | 栏目数据中的来源热播榜（统计窗口未确认） | 页面按 `MOD_818368` 提取且校验 categoryId |
| `play` | 组合调用，不是单个上游路径 | 剧集、清晰度、交换凭证、解析及媒体身份校验 | 详情页实际播放入口 |

当前新版分类发现通过目录、热搜数据和分类关键词检索实现；没有调用 `/category/type/listActive`、`/category/filter/dimensions` 等独立分类管理端点。

内部辅助路径还包括：

- `POST /auth/negotiate`：SDK 握手与会话准备，不是用户账号登录。
- `POST /ad/getConfig`、`POST /ad/claimReward`：`play` 的受限 SDK 路径；只接受固定 `player_switch_episode` 槽位与 `privilege_supply` 任务，不是应用已接入完整广告奖励体系，也没有任意奖励调用入口。代码中有这些路径不意味着本次播放触发过它们。
- 客户端解析：原始 SDK `PARSE_API` 为 `http://106.52.75.47/jx/jsoncnm.php?url=`，按播放材料决定是否使用。
- 返回的媒体/CDN URL：动态资源，播放时使用来源请求头；不算固定业务接口。

运行层 11 个操作对应 10 个直接业务端点；再加内部握手与 2 个条件性广告路径，代码链路涉及 13 个不同上游路径。它们的执行条件不同，不应当作 13 个同级页面功能。

### 尚未接入的 MioMedia 领域

登录、注册、邮箱绑定、密码与验证码、账号资料/消息、收藏与历史上报、影评/评论写入、弹幕发送、会员、钱包、任务签到、邀请福利、下载配额与下载凭证等，尚未作为当前应用页面业务接入。

仓库 `docs/miomedia-endpoint-inventory.json` 记录了 132 个文档端点（130 POST、2 GET），其 Markdown 为 2026-10-12 的历史核验快照，开头“7 个公开操作”已落后于当前 11 个操作。保留历史记录，不将文档数量解释为接入数量。

## 2. Bangumi：资料、日历与收藏同步

代码：`lib/request/config/api_endpoints.dart`、`lib/request/apis/bangumi_api.dart`、`lib/presentation/modern/home/home_catalog.dart`、`lib/services/calendar/calendar_service.dart`。

| 服务 | 路径与方法 | 当前用途 |
| --- | --- | --- |
| `api.bgm.tv` | POST `/v0/search/subjects` | 搜索、排行榜、历史季度筛选、推荐补充 |
| `api.bgm.tv` | GET `/v0/subjects` | 首页排行/列表的兼容兜底 |
| `api.bgm.tv` | GET `/v0/subjects/{id}/subjects` | 关联作品 |
| `api.bgm.tv` | GET `/v0/subjects/{id}/characters` | 条目角色 |
| `api.bgm.tv` | GET `/v0/subjects/{id}/persons` | 工作人员 |
| `api.bgm.tv` | GET `/v0/episodes` | 剧集元数据 |
| `next.bgm.tv` | GET `/p1/calendar` | 每日放送/当前季度日历 |
| `next.bgm.tv` | GET `/p1/trending/subjects` | 趋势/热榜 |
| `next.bgm.tv` | GET `/p1/subjects/{id}` | 条目详情、日历数据补充 |
| `next.bgm.tv` | GET `/p1/subjects/{id}/comments` | 作品评论读取 |
| `next.bgm.tv` | GET `/p1/episodes/{id}/comments` | 剧集评论读取 |
| `next.bgm.tv` | GET `/p1/characters/{id}`、`/p1/characters/{id}/comments` | 角色详情及评论 |
| 鉴权域 `api.bgmapi.com` | GET `/v0/me` | Access Token 对应用户校验 |
| 鉴权域 `api.bgmapi.com` | GET `/v0/users/{username}/collections` | 拉取收藏 |
| 鉴权域 `api.bgmapi.com` | POST `/v0/users/-/collections/{id}` | 现有实现写入收藏状态、评分/评价 |
| 镜像 `api.kazumi.fyi` | GET `/kazumi/v1/popular/subjects`、`/kazumi/v1/calendar/season` | 镜像榜单与历史季度日历 |

只在常量中定义的 URL 不能直接算已调用。例如 `/v0/subjects/{id}` 常量仍存在，但 `getBangumiInfoByID` 当前实际取 `/p1/subjects/{id}`。

原生有 direct/ECH/mirror 请求策略；Web 走同源网关。鉴权使用用户配置的 Bearer Token，应用没有自行实现 Bangumi 的账号注册/密码登录。MioMedia 收藏、历史、弹幕也没有自动关联到这套 Bangumi 身份。

## 3. 弹幕与以图搜番

| 服务 | 已接入接口 | 说明 |
| --- | --- | --- |
| 弹弹play `api.dandanplay.net` | GET `/api/v2/search/episodes` | 按名称搜索弹幕作品/剧集 |
| 弹弹play | GET `/api/v2/bangumi/{id}` | 获取剧集列表 |
| 弹弹play | GET `/api/v2/bangumi/bgmtv/{id}` | Bangumi ID 映射 |
| 弹弹play | GET `/api/v2/comment/{episodeId}` | 拉取弹幕；请求含 `withRelated=true` 和繁简转换参数 |
| trace.moe `api.trace.moe` | POST `/search` | 图片字节或图片 URL 识别番剧 |

弹弹play请求附加 AppId、时间戳和签名；凭据值不写入清单。播放器中的 BiliBili/Gamer 来源开关是在筛选弹弹play返回的聚合弹幕，当前代码没有独立请求这两个平台的官方 API。

代码：`lib/request/apis/danmaku_api.dart`、`lib/request/clients/danmaku_client.dart`、`lib/pages/player/player_item.dart`、`lib/request/apis/trace_api.dart`、`lib/pages/search/search_controller.dart`。

## 4. 规则站点：16 份内置规则

统计对象是版本库 `assets/plugins/*.json`，不是本机用户实际启用列表；多个规则可能共享站点。

14 份搜索规则采用 XPath 网页解析：7sefun、aafun、AGE、akianime、baimao、dalvdm、DM84、ezdmw、giriGiriLove、mgnacg、moonci、mutefun、MXdm、xfdmneo。它们是网页采集与播放器解析链路，不是 14 家正式 JSON API。

另外 2 份采用 API 搜索/剧集规则：

| 规则 | 方法/URL | 用途 |
| --- | --- | --- |
| sorani | GET `https://api.sorani.cc/sorani-cms/api/video` | 搜索 |
| sorani | GET `https://api.sorani.cc/sorani-cms/api/video/{source}` | 作品和剧集 |
| xfdmnext | POST `https://api.xifanacg.com/rest/v1/rpc/search_animes` | 搜索 RPC |
| xfdmnext | POST `https://api.xifanacg.com/rest/v1/rpc/get_anime_detail` | 详情/剧集 RPC |

规则有公开客户端请求头配置，本清单不复制其凭据字段。当前库存和本机启用状态、站点是否在线、是否能播放是三种不同口径。

## 5. 更新、同步与同播

- **应用更新**：GET `https://api.github.com/repos/haigepor/Playra/releases/latest`，再按发布资产 URL 下载；当前 Playra 发布源由 `AppBrand` 管理，沿用 Kazumi 的规则仓库。之前安卓启动日志出现过该更新接口 404，这不代表应用内容加载失败。
- **规则目录/更新**：GitHub Raw 的 `Predidit/KazumiRules/main/index.json` 和 `{ruleName}.json`；配置有 GitCode 镜像。代码在 `PluginCatalogApi` 和 `RulesRepoClient`。
- **WebDAV**：用户配置 URL、用户名和密码；读取目录、下载/上传文件、建目录、移动和删除，支持备份、观看历史/收藏及弹幕屏蔽同步。不是固定 Playra 云账号服务。
- **Syncplay**：原生 Socket/STARTTLS 协议，同播房间、播放状态和聊天。默认 `syncplay.pl:8996`，另有 8995/8997/8998/8999。不是 REST，也没有新增 WebSocket 服务来支持浏览器同播。

## 6. 本地接口分层

### Web Node 网关

代码：`tool/web_backend/server.cjs`、`runtime.cjs`。

| 接口 | 用途 |
| --- | --- |
| `/api/health` | Node 服务健康 |
| `/api/proxy` | 代理 HTTP、图片、视频、HLS 子资源；保留来源请求头 |
| POST `/api/parse` | Chromium 视频地址解析 |
| POST `/api/captcha` | 浏览器验证码/验证上下文 |
| `/api/runtime/v1/*` | 固定转发 Python Runtime 契约 |
| `/api/v1/*` | 转发独立 Dart 来源 HTTP 服务 |

最新页面使用新版预览端口 8933；标准 Web 启动脚本默认 8931。端口可配置，不能写成其他设备的固定地址。Node 默认 Dart 来源 API 端口 8940；Python Runtime 本次使用 8945。声明了转发路由不代表对应后端进程已经启动。

### Dart 来源 HTTP API

代码：`lib/services/source/source_http_server.dart`、`source_http_client.dart`。

- GET `/api/v1/health`；POST `/api/v1/sessions`。
- GET `/api/v1/sources`、`/api/v1/sources/{id}`、`/health`、`/categories`、`/search`、`/contents`（后四项相对单来源路径）。
- GET `/api/v1/sources/{id}/contents/{contentId}`、`/lines`；GET `/api/v1/search` 聚合检索。
- POST `/api/v1/playback/resolutions`；GET/DELETE `/api/v1/playback/resolutions/{id}`。
- POST `/api/v1/challenges`；GET/DELETE `/api/v1/challenges/{id}`；POST `/api/v1/challenges/{id}/submissions`。
- GET/HEAD `/api/v1/media/{ticket}`：有时效的媒体引用与 HLS 转发。

这是通用规则来源服务，有独立来源会话；当前 MioMedia 页面直接调用 SDK Runtime，并不把该通用服务当成必需前置。

### Python Runtime 与 Android 内嵌桥接

- GET `/v1/health`、`/v1/adapters`。
- POST `/v1/adapters/miomedia/sdk`：`{operation,payload}`，只开放上面 11 个操作。
- 通用 GET `/v1/adapters/{id}/search`、`/episodes`，POST `/resolve` 为契约骨架：当前 MioMedia adapter 只声明 `sdk` 能力，不能把这三个通用路由算作 MioMedia 已开放接口。
- registry 有 `template` 和 `miomedia` 两项；`template.implemented=false`、无业务能力，因此不是两个已完成 SDK。
- Android 通过 `com.predidit.kazumi/source-runtime` MethodChannel 的 `request` / `cancel` 调 Chaquopy 内嵌 Python，无需依赖桌面 Python 服务。

## 结论与验证边界

已通过源码引用、AST 提取 `OPERATIONS` 和结构化解析内置规则核对数量。没有发送账号、收藏、评论、奖励、支付或其他写请求；没有扫描本机用户令牌/密码。SDK 与 Web 播放的已有实测证据、安卓用户实测分别记录在播放器报告。

需要持续区分：已在代码中实现、已在页面使用、已配置并启动、已远端实测。这次只做接口梳理，没有新增接口或改动业务配置。

如果下一阶段开发 MioMedia 的账户/会员/社区，应先明确账号登录、令牌管理、错误码和作品身份边界；它们无法直接复用 Bangumi Token 与收藏表。
