# Web / Android 来源算法运行骨架

> 新来源的完整接入流程见[内容 SDK 与接口接入规范](development/source-sdk-onboarding.zh.md)。本文说明传输与算法运行层；通用 SDK 播放页已建立，但 `sdk` 路由和 Android 内置 SDK 分发当前仍为 Mio 专用，新增 SDK 必须显式补齐各平台传输。

更新：2026-10-13。所有命令从当前设备的仓库根目录执行；工具位置与多设备迁移统一参照 [开发环境与路径说明](development/web-android-environment.zh.md)。

## 当前边界

已建立 Flutter 请求入口、Web 固定桥接、Python 适配器与 Android 内置运行时。Web 的 Python 在电脑或服务端运行；Android 默认通过 Kotlin/Chaquopy 在 APK 内调用 SDK，无需电脑服务。MioMedia 已接入 11 个受限 SDK 操作，见 [当前代码与 SDK 分析](analysis/web-android-sdk-20261013.zh.md)。模板适配器仍没有真实资源，其能力列表为空，业务请求返回 `UNSUPPORTED`。

示例规则不自动导入、不进入内置规则目录。原有 16 条动漫规则仍交给原请求器。本次没有改变来源排名、首页分类和播放器界面。

## 调用关系

```text
普通来源页面 → SourceService → RuleEngine → SourceRuntimeExecutor
  普通规则 URL → 原平台请求器
  https://source-runtime.playra.invalid/v1/... → 算法服务
    Web：同源 /api/runtime/v1/... → Node 固定桥接 → Python
    Android：显式外部地址才走 HTTP；模板不提供资源
MioMedia 页面 → MioMediaService → SourceRuntimeClient
  Web：同源 Node 桥接 → Python SDK
  Android：MethodChannel → Kotlin → Chaquopy/Python SDK
```

`source-runtime.playra.invalid` 是显式规则标记，不是需要解析的实际域名。HTTP 服务允许 `/v1/health`、`/v1/adapters`、登记适配器的 `search / episodes / resolve` 路由，以及固定 MioMedia `sdk` 路由。它与项目既有“对外来源 HTTP API”职责不同：前者运行某个适配器，后者对外提供统一来源服务。

## 本机启动 Web

需要完整私有 SDK 和 Python 3.11 / Node 22 / 项目指定 Flutter。先按环境说明准备本机配置；每个终端分别激活。

终端一（保持运行）：

```powershell
. ./tool/use-dev-env.ps1
python -B -X utf8 tool/source_runtime/server.py --port 8945
```

终端二：

```powershell
.\tool\start-web.ps1 -Port 8931 -RuntimePort 8945 -Build
Invoke-RestMethod 'http://127.0.0.1:8931/api/runtime/v1/health'
```

服务健康响应应包含 `service: playra-source-runtime`、`apiVersion: 1`、`status: ok`。健康成功只说明协议已启动，不说明适配器已有可用资源。

Web 默认使用当前页面同源 `/api/runtime/v1/`，无需在规则里写机器地址。`-RuntimePort` 是显式启用开关；不启用时固定桥接返回 `RUNTIME_UNAVAILABLE`。已运行的旧 Web 服务不会自动被杀掉；若未启用运行桥接，需自行停止对应服务并重启，或使用另一端口。Python 默认仅监听 `127.0.0.1`；关闭 Python 终端即可停止算法服务。

## Android 开发连接

Android 默认使用 APK 内置 SDK，直接运行 `./tool/build-android.ps1` 即可。只有需要调试外部 HTTP 服务时，才在构建时传入服务基址，尾部包含协议路径 `/v1/`。

连接设备并通过 USB 调试时，可执行：

```powershell
. ./tool/use-dev-env.ps1
adb reverse tcp:8945 tcp:8945
.\tool\build-android.ps1 `
  -RuntimeUrl 'http://127.0.0.1:8945/v1/' -RuntimeAllowHttp
```

脚本将参数转换为 `PLAYRA_SOURCE_RUNTIME_URL`、`PLAYRA_SOURCE_RUNTIME_ALLOW_HTTP` 的 Dart 构建配置。工具链路径按实际设备修改。没有连接设备时不能将电脑的 `127.0.0.1` 当成手机可达地址；`adb reverse` 只用于调试，需要 Python 服务持续运行。

后续生产部署使用 HTTPS，例如 `-RuntimeUrl 'https://your-service.example/v1/' -Release`，不传 `-RuntimeAllowHttp`。本次 Python 标准库服务器用于本地开发，尚未实现公网鉴权、租户隔离、密钥管理、会话持久化或生产部署。[Python 官方 http.server 文档](https://docs.python.org/3.13/library/http.server.html)说明该服务器不适合生产使用。

## 适配器接口

| 方法与路径 | 请求 | 成功响应 |
| --- | --- | --- |
| `GET /v1/health` | 无 | `service / status / apiVersion / adapters` |
| `GET /v1/adapters` | 无 | `data: [{id, version, domains, capabilities, implemented}]` |
| `GET /v1/adapters/{id}/search` | `q, page, pageSize` | `data: [{name, url}], total, hasMore` |
| `GET /v1/adapters/{id}/episodes` | `source` | `data: {roads: [{name, episodes: [{name, url}]}]}` |
| `POST /v1/adapters/{id}/resolve` | JSON `{episodeUrl}` | `data: {url, headers, format, expiresAt}` |
| `POST /v1/adapters/miomedia/sdk` | JSON `{operation, payload}` | `data` 与 `meta` |

业务请求必须携带 `X-Kazumi-Request: 1`；Flutter 和 Web 桥接自动添加。`X-Playra-Timeout-Ms` 为 1–60000 毫秒，默认总预算 20 秒。Web 桥接最大预算 20 秒。错误响应为 `{"error":{"code":"UNSUPPORTED","message":"UNSUPPORTED"}}`，不会返回原始异常或密钥。

错误码包括 `RUNTIME_UNAVAILABLE`、`UNSUPPORTED`、`INVALID_ARGUMENT`、`TIMEOUT`、`CANCELLED`、`BUSY`、`PARSE_ERROR`、`RUNTIME_ERROR`；真实算法可返回 `DECRYPT_ERROR` 等大写业务码。无资源应成功返回空 `data`，与运行不可用、解密失败分开。规则执行层保留上述错误码。

请求体上限 32 KiB，响应上限 2 MiB，Python 操作并发上限 4。请求取消、断开和超时传递到 `RuntimeContext`；适配器必须主动检查上下文，并为自己的 HTTP 请求配置剩余超时时间。线程不能强行终止忽略取消的 Python 算法，该任务仍占并发名额，避免超时后无限启动线程。CPU 密集型或不可取消算法接入时，应再改为隔离进程执行。

## 新增其他适配器的接入顺序

1. 在 `tool/source_runtime/adapters.py` 新建受维护的适配器类，显式登记到 `registered_adapters()`；不要通过请求上传或指定可执行脚本。
2. 明确真实来源身份、媒体域和已实现能力，提供对应的 `manifest()`，完成后将 `implemented` 设为真实状态。当前模板使用 `screen` 域；示例规则 `type: movie`。电视剧接入时应按现有领域模型单独声明，不能把所有影视结果都归为电影。
3. 实现 `search / episodes / resolve`；签名与响应解密放在适配器内部的 `sign_request / decode_response`，不要将密钥写入规则 JSON。
4. 返回真实线路名、真实剧集名与稳定标识，保留特殊集、分集顺序。不要用显示位置猜测跨来源集数对应关系。
5. 从 `tool/source_runtime/example-rule.json` 复制规则，更换适配器 ID、来源 ID、类型和能力映射；完成真实接口检查后再导入。模板本身不可用于观看。
6. 需要站点 cookie、验证码或登录状态时，补齐受控会话与鉴权设计，再开放能力；本次不伪造会话成功。

解析返回的 `headers` 用于后续媒体请求，不是运行服务鉴权头。Web 能否播放仍取决于媒体 URL、CORS 和既有播放器能力，不能由算法健康状态推断。

## 验证与回滚

实际检查记录见 `docs/verification/source-algorithm-runtime.zh.md`。本次六个既有文件的修改前副本位于 `.dart_tool/runtime-skeleton-before-20261012/`。该目录不进入版本库，应在清理构建缓存前另行保留。只回退本次差异，不要对已有大量未提交改动执行整体重置。
