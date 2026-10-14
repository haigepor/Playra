# MioMedia SDK 封装接入

> 新 SDK / 新接口接入统一从[内容 SDK 与接口接入规范](development/source-sdk-onboarding.zh.md)开始；2026-10-14 的播放源分层、自动选线和共享页面实现见[实施记录](analysis/sdk-provider-lines-quality-implementation-20261014.zh.md)。以下第一阶段记录保留为历史，不作为新增 SDK 的公共播放契约。

日期：2026-10-12。本文件记录第一阶段 SDK 封装与接口数据整理。

后续已接入播放模块、影视首页、搜索、资料和播放器，当前源码为 11 个受限操作。当前分析见 [Web/Android 与 SDK](analysis/web-android-sdk-20261013.zh.md)，本机与其他设备的路径参照 [开发环境说明](development/web-android-environment.zh.md)。下文 7 个操作、外部 HTTP Android 方案及 `playbackReady=false` 均是第一阶段历史结果。

## 完成范围

Python 服务内携带 `vendor/miomedia`，SDK 算法和二进制表保持原样。仅 `profile.py`、`config.py` 增加 TODO，保留用户提供的默认环境值用于联调。平台分配参数、正式包名、签名摘要待替换。

新增受限 HTTP SDK 操作入口，并为 Flutter 提供 `SourceRuntimeClient.callMioMedia()`。Web 使用既有同源桥接，Android 使用既有构建运行地址。当前尚未绑定首页、资料、搜索和播放器 UI；来源清单显示 `sdk` 能力，不将它安装为具备完整搜索/播放能力的旧规则。

## 启动与调用

终端一：

```powershell
# 从当前设备的仓库根目录执行；先准备本机环境配置。
. ./tool/use-dev-env.ps1
python -B -X utf8 tool/source_runtime/server.py --port 8945
```

终端二：

```powershell
.\tool\start-web.ps1 -Port 8931 -RuntimePort 8945 -NoOpen
$mioBody = @{ operation='recommend'; payload=@{} } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:8931/api/runtime/v1/adapters/miomedia/sdk' `
  -ContentType 'application/json' -Headers @{'X-Kazumi-Request'='1'} -Body $mioBody
```

若原端口已运行旧服务，应选择另一端口或停止对应旧服务后重启。启动器不会替用户杀掉现有服务。

Flutter 调用：

```dart
final runtime = SourceRuntimeClient();
final recommended = await runtime.callMioMedia('recommend');
final detail = await runtime.callMioMedia('detail', payload: {
  'videoId': '329257153645817856', // 示例；替换为列表返回的字符串 ID。
});
// 有自己的生命周期所有权时，离开服务后调用 runtime.dispose()。
```

本阶段 Android 使用外部 HTTP；当前源码默认使用内置 Python，只有显式外部调试才配置运行地址与 `adb reverse`，见 `docs/source-algorithm-runtime.zh.md`。SDK 服务整体使用 Python 3.11+；原 SDK 声明自身兼容 Python 3.8+。本阶段记录未重新打包或安装 Android APK。

## 固定操作契约

Python：`POST /v1/adapters/miomedia/sdk`。
Web：`POST /api/runtime/v1/adapters/miomedia/sdk`。

正文必须为 `{"operation":"recommend","payload":{}}`，只允许下表操作和参数。SDK 自动在内部完成 `/auth/negotiate`、签名、指纹与加解密，握手密钥不会返回给客户端。

| operation | SDK 上游路径 | payload | 已验证返回 data |
| --- | --- | --- | --- |
| recommend | `/home/recommend` | `{}` | `guessYouLike`：标题、videos、hasMore、pageinfo；本轮 10 条 |
| banners | `/banner/list` | `{}` | `banners` 轮播列表；本轮 20 条 |
| catalog | `/video/categoryList` | `{}`，可传 `pageIndex/pageSize` | `videos/pageinfo`；默认调用本轮 10 条，分页语义尚待验证 |
| detail | `/video/detail` | `{videoId}` | `video` 完整作品资料，线路在 `video.player` |
| episodes | `/resolve/episodes` | `{videoId,code}` | `episodes`；实际检查作品的一条线路有 288 集 |
| qualities | `/resolve/qualities` | `{videoId,code,episodeNum,caps:[]}` | `qualities/exchangeToken/expiresAt/isClientParse` |
| exchange | `/resolve/exchange` | `{videoId,code,episodeNum,quality,exchangeToken,caps:[]}` | `playUrl/quality/expiresIn/isClientParse/luaScript/originalUrl` |

`videoId` 必须保持字符串，不转换成 Bangumi ID 或 Web 数字。集数按实际 `episodeNum`，线路按实际 `code`，不能按显示位置推断。当前明确只声明空 `caps`，没有实现 `v2ts` 能力。

返回形式：`{"data":{...},"meta":{"providerId":"miomedia","operation":"recommend"}}`。data 保留真实内容字段，删除设备身份、会话密钥和算法配置等私有字段。解析脚本是被动数据，本轮没有执行。

## 身份、会话与错误

- 首次内容请求生成 `.dart_tool/miomedia/device.json`；之后及服务重启复用。身份文件不包含派生密钥。错误文件返回 `IDENTITY_ERROR`，不会覆盖重建。
- 当前身份作用域为一个本地服务实例。远程多设备/多用户部署需要后续增加会话隔离与鉴权，不能让全部用户共用本地服务身份。
- 同时发起的首次请求共用一次握手。会话状态缓存 300 秒；每个业务请求使用同身份的独立 SDK Client，避免并发修改 timeout 与校时状态。
- 握手校验 HTTP 200、业务 code=200/success=true、设备 ID、派生密钥、协议 v3、serverTime 与 keyVersion。配置版本不一致返回 `SESSION_CONFIG_MISMATCH`，需要取得平台新配置，不能循环使用旧密钥。
- 只读内容请求的网络错误最多额外重试一次，受运行总预算限制。业务拒绝、解密失败不重试。`4031` 映射 `AD_REQUIRED`，不伪造广告完成。
- 其他错误包括 `UPSTREAM_NOT_FOUND`、`UPSTREAM_HTTP_ERROR`、`UPSTREAM_UNAVAILABLE`、`BUSINESS_REJECTED`、`DECRYPT_ERROR`、`PARSE_ERROR`、`SESSION_MISMATCH`、`TIMEOUT`、`CANCELLED`。客户端收到固定错误码，不收到上游敏感异常文本。
- SDK 使用 socket 超时与合作式取消；取消后不发布结果，但不能强杀正在执行的标准库网络调用。既有线程名额和 HTTP 总预算仍生效。

可通过管理员环境变量 `PLAYRA_MIOMEDIA_STATE_DIR` 更改身份目录、`PLAYRA_MIOMEDIA_BASE_URL` 更改接入点。这些不是 HTTP 调用者可覆盖的字段。

## 132 个文档端点与 7 个公开操作

端点总数按提供的所有接口文档去重统计，为 **132 个：130 POST＋2 GET**，不代表全部经过联调或全部已开放。两个 GET 是会话配置资源 `auth/bootstrap.jpg` 和另一个接入点的版本检查 `check-update`。

完整逐项清单、用途和已知数据说明见 `docs/miomedia-endpoint-inventory.zh.md` 与对应 JSON。只有本页 7 个内容操作暴露给运行客户端；账号、评论发布、会员、钱包、广告写操作等未开放。

## 后续页面集成的边界

SDK 操作成功与实际播放成功是不同验收项。本轮 exchange 返回 `isClientParse=true`、空 playUrl、有客户端解析材料；manifest 明确 `playbackReady=false`。需要取得客户端解析契约或可直接播放的 URL 后再集成媒体播放。

实际 `video/detail` 线路位于 `video.player`，剧集由 `resolve/episodes` 单独取得。文档中的 `category/types` 在上一轮实际检查返回 404，分类与搜索请求参数也需要后续核验。首页应继续独立增量加载，不等待所有目录请求结束。

## 修改清单与回滚

六个既有文件：`tool/source_runtime/{adapters.py,server.py}`、`tool/web_backend/{runtime.cjs,runtime.test.cjs}`、`lib/services/source/runtime/source_runtime.dart`、`test/source_runtime_test.dart`。分别负责登记、固定路由、Web 桥接、Flutter 方法与对应回归。

新增 SDK vendor、`miomedia_adapter.py`、单元/加密 HTTP 检查、`miomedia_live_check.py`、`endpoint_inventory.py`、`tool/miomedia_runtime_integration.dart`、文档和 OpenSpec 变更。SDK 未引入第三方运行依赖；原有 16 条动漫规则与 UI 保持原样。

回滚副本与本轮前哈希位于 `.dart_tool/miomedia-sdk-before-20261012/`。只恢复本轮差异，不重置已有工作区。需要保留身份时另行保存 `.dart_tool/miomedia/device.json`；清理该文件后将产生新身份。
