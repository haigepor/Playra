# Web / Android 算法运行时参考

更新：2026-10-15。后续接入统一遵循[SDK 接入规范](development/source-sdk-onboarding.zh.md)，并提交[接入验收记录](development/templates/source-sdk-checklist.zh.md)。本文只说明当前运行协议和本机服务，不另定义业务模型。

## 当前组成

- SDK 家族：MioMedia、AniFive；可执行业务 adapter 为 `miomedia`、`anifive-a/b/c/d`，另有无资源 `template` 占位。
- 内置动漫规则为4源；普通自定义规则仍使用原请求器，显式运行标记域名才进入算法服务。
- `dispatch.py` 共用 `search/episodes/resolve` 的字段校验和执行映射；`sdk` 扩展当前仅允许 Mio。
- Python HTTP 的注册表在 `adapters.py`；APK 内注册表在 `android_bridge.py`。新增来源必须同时核对，不能只改其中一个。
- 本机算法服务、对外来源HTTP API、媒体代理和Bangumi ECH是不同组件，路径不能互换。

| 组件 | 当前入口 / 默认地址 | 职责 |
|---|---|---|
| Web Node | `tool/start-web.ps1` / `http://127.0.0.1:8931` | Flutter静态资源、同源运行桥、媒体/图片代理 |
| Python算法 | `tool/source_runtime/server.py` / `http://127.0.0.1:8945/v1/` | 固定Adapter与私有SDK执行 |
| Bangumi ECH | `tool/bangumi_web_bridge.dart` / `http://127.0.0.1:8946` | 固定Bangumi公开域名资料/图片网络通道 |
| 来源HTTP API | `tool/source_api.dart` / `http://127.0.0.1:8940/api/v1/` | 来源会话、统一检索/目录/媒体票据；[独立文档](source-http-api.md) |
| Android内置 | `com.predidit.kazumi/source-runtime` | MethodChannel→Kotlin→Chaquopy；不监听本机HTTP端口 |

这些端口是本机开发默认值，不是供应商接口数量，也不是移动端需要连接的服务器清单。

## Web 启动与验证

先准备[私有构建输入](release/build-inputs.zh.md)及[开发环境](development/web-android-environment.zh.md)，从仓库根目录执行：

```powershell
. ./tool/use-dev-env.ps1
./tool/start-web.ps1 -Port 8931 -RuntimePort 8945 -BangumiEchPort 8946 -Build
Invoke-RestMethod 'http://127.0.0.1:8931/api/health'
Invoke-RestMethod 'http://127.0.0.1:8931/api/runtime/v1/health'
Invoke-RestMethod 'http://127.0.0.1:8946/health'
```

当前启动器自动检查/启动Python与ECH服务，随后启动Node；不必先手工开Python终端。`-NoOpen`不打开浏览器；`RuntimePort=0/BangumiEchPort=0`跳过对应启动。启动器不会更新已有进程的代码/环境；已启动旧服务时，按其PID和所属命令确认后停止并重启，或使用新端口。

日志和PID保存在 `.dart_tool/web-service/`。启动器检查输入文件存在和服务健康，不会自动执行完整SDK自检，也不会自动准备完整的来源HTTP API。单纯 `flutter build web` 后用任意静态服务器打开，不包含这些服务。

需要单独运行服务进行调试时：

```powershell
. ./tool/use-dev-env.ps1
python -B -X utf8 tool/source_runtime/server.py --port 8945
# 另一个终端激活同样环境后运行：
dart run tool/bangumi_web_bridge.dart 8946
```

手工启动Node时，环境映射为 `KAZUMI_WEB_PORT`、`PLAYRA_SOURCE_RUNTIME_PORT`、`PLAYRA_BANGUMI_ECH_PORT`；未配置runtime端口时Node返回 `RUNTIME_UNAVAILABLE`。Node直接启动的Web端口默认8930，PowerShell启动器默认8931，二者不要混淆。

Web调用链：

```text
Plugin运行标记 / 供应商Service → SourceRuntimeClient
 → 同源 /api/runtime/v1/* → runtime.cjs
 → 固定loopback /v1/* → server.py → dispatch.py → Adapter → SDK
解析媒体 → 原播放器 → /api/proxy → 媒体CDN
Bangumi资料/图片 → /api/proxy → 固定ECH桥（启用时）
```

ECH服务只接收 `api.bgm.tv / next.bgm.tv / lain.bgm.tv` 的HTTPS请求，POST只允许 `api.bgm.tv/v0/search/subjects`，不转发Cookie/Authorization，不负责SDK协议。第三方封面失败不能一律归因于ECH。

## Android 内置与外部调试

默认构建：

```powershell
. ./tool/use-dev-env.ps1
./tool/build-android.ps1
```

`stageEmbeddedPython`检查Mio和AniFive模块，显式复制需要的Python及数据资源到Chaquopy源集；Python版本3.11，当前ABI为 `armeabi-v7a/arm64-v8a/x86_64`。运行数据放应用私有目录，保留既有applicationId、MethodChannel和数据路径兼容。

默认调用链：

```text
SourceRuntimeClient（endpoint为空）→ embedded_runtime.dart
 → request(requestId,payloadJson,timeoutMs)
 → SourceRuntimeBridge.kt → android_bridge.configure(filesDir)
 → AndroidRuntime.request → registry → dispatch.operation → Adapter
```

JSON请求必须包含且仅包含：

```json
{"path":"adapters/anifive-a/search","method":"GET","query":{"q":"示例作品","page":1,"pageSize":20},"body":null}
```

requestId为1–64位字母/数字/下划线/连字符，不属于业务参数；`cancel`复用该ID。业务执行池4线程、等待队列8名额；排队时间算入总预算；取消通过独立线程触达Python。每个SDK独立持有设备状态和会话。

仅调试外部HTTP服务时：

```powershell
. ./tool/use-dev-env.ps1
adb reverse tcp:8945 tcp:8945
./tool/build-android.ps1 -RuntimeUrl 'http://127.0.0.1:8945/v1/' -RuntimeAllowHttp
```

`RuntimeUrl`写入 `PLAYRA_SOURCE_RUNTIME_URL`；允许HTTP需显式开发开关。无 `adb reverse` 时电脑loopback不等于手机loopback。生产外部服务需HTTPS和独立鉴权方案；iOS/桌面当前没有Android式内置桥。

## 固定业务契约

| 方法 / 路径 | 请求 | 成功响应 |
|---|---|---|
| `GET /v1/health` | 无query | HTTP为 `{service,status,apiVersion,adapters}` |
| `GET /v1/adapters` | 无query | HTTP为 `{data:[manifest...]}` |
| `GET /v1/adapters/{id}/search` | `q,page,pageSize` | `{data:[{name,url,cover?}],total,hasMore,paginationMode?}` |
| `GET /v1/adapters/{id}/episodes` | 仅 `source` | `{data:{roads:[{name,episodes:[{name,url}]}]}}` |
| `POST /v1/adapters/{id}/resolve` | 仅JSON `{episodeUrl}` | `{data:{url,headers,format,headerPolicy?,expiresAt?}}` |
| `POST /v1/adapters/miomedia/sdk` | 仅JSON `{operation,payload}` | 供应商公开data/meta；play结果含status/selection/media |

业务HTTP请求须带 `X-Kazumi-Request: 1`；JSON POST不允许额外字段。`q`≤300字符，`page`为1–1000000，`pageSize`为1–100，引用通用上限8192字符，Adapter可进一步收紧。HTTP拒绝重复query字段；业务ID不可由请求指定模块/脚本/命令代替。

**已有差异**：Android health返回 `{data:{service,apiVersion,embedded}}`，adapters返回 `{data:{adapters:[...]}}`；非Mio sdk非法路由在HTTP/Android上的拒绝码也可能不同。普通业务成功结构共用dispatch，但尚未完全归一化所有健康/非法路由外壳。新增调用应显式解析当前平台或先补兼容归一化，不要假设整个响应逐字节一致。

`headerPolicy=replace`表示返回媒体头替换默认站点头；空headers也不能补回Referer/Origin/Cookie。旧规则未声明时保留默认合并。四源返回 `format=hls/auto`；只有硬过期才输出expiresAt。

## 预算、错误与网络边界

- `X-Playra-Timeout-Ms`为1–60000毫秒，运行客户端/Python默认20秒；Node桥最多20秒。总预算包括连接、读取、锁/队列等待。
- 协议请求体32KiB、响应2MiB；Python HTTP默认8个执行名额。业务忽略取消时仍占名额，不能在外部超时后无限新建线程。
- `RuntimeContext.check_active()`贯穿工作；HTTP断开、Dart取消和原生取消必须停止后续副作用。阻塞的系统DNS/第三方算法不保证瞬时停止，不能据此宣称强制中断能力。
- 统一错误为 `{"error":{"code":"TIMEOUT","message":"TIMEOUT"}}`；Dart接受 `[A-Z_]{1,64}` 的公开码。HTTP另有状态码；Android返回JSON错误，不依赖HTTP状态。
- 无结果返回成功空集合；超时、解密失败、服务缺失不能伪装空结果。完整错误表见[主规范第7节](development/source-sdk-onboarding.zh.md#7-超时取消会话和错误处理)。
- 私有SDK、设备身份、token、签名媒体地址不得写进公开规则/日志。SDK密钥和会话按供应商隔离。
- AniFive元数据传输限制维护者主机、公网地址、TLS及响应大小；媒体探测上限4096字节。Web媒体代理仍执行自己的公网/端口策略，必须分别验收。

## 注册和验收顺序

通用三操作：新增Adapter与manifest → HTTP注册 → Android私有状态/注册 → Gradle依赖及打包白名单 → 动漫规则或业务Service → 聚合入口 → 两端实播。需要新增 `sdk` 扩展时，还须同步Dart accepts、Node allowed、HTTP/dispatch的操作和字段白名单；不要借用Mio入口。

协议专项命令：

```powershell
. ./tool/use-dev-env.ps1
python -B -X utf8 -m unittest discover -s tool/source_runtime -p 'test_*.py'
node --test tool/web_backend/*.test.cjs
dart run tool/source_runtime_integration.dart $env:PLAYRA_BUILD_PYTHON
```

接入记录分别列构建、协议、媒体探测、Web首帧/持续播放、Android首帧/持续播放。接口健康或SDK自检不能代替实际播放器验收。当前四源Android持续播放和AniFive CI私有输入仍待补齐，见[主规范的当前差距](development/source-sdk-onboarding.zh.md#12-当前差距与后续优先项)。

回退使用对应接入记录里的代码/来源策略备份，保留历史、收藏和自定义规则。旧骨架阶段记录保存在[历史验收](verification/source-algorithm-runtime.zh.md)，其中旧并发/来源数量不能作为当前运行事实。
