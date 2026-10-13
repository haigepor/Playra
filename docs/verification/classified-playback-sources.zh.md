# 来源分类与播放调度交付记录

日期：2026-10-11。项目：`C:/Users/haige/Desktop/Playra`。
OpenSpec：`classify-and-schedule-playback-sources`。

## 本次实施

- 16 条本机规则仍保留原始 JSON，全部从显式 `type: anime` 生成动漫领域；没有重写、删减或合并安装规则。名单与站点见 `docs/design/source-classification-playback-policy.zh.md` 的归档表。Web、Android、Windows 的安装列表独立。
- 领域使用 `anime` / `screen`，没有声明的来源为未分类；影视领域覆盖电影、电视剧、综艺、纪录片、漫剧。规则管理支持分类筛选、独立启停及动漫/影视/双领域/未分类覆盖。
- 本地覆盖和近期样本保存到应用插件目录的 `v2/source-policy.json`，远程规则更新不覆盖这些设置；规则版本改变后不再使用旧版本速度样本。导出旧规则 JSON 不包含这些本地覆盖，需要跨设备迁移时单独保存策略文件。
- 播放检索按作品领域过滤，最多 4 个工作者。标题和别名仅去除空白、符号，不删除季号、年份或 SP/OVA。预取剧集并移除空名称/空地址，确认无匹配作品或无有效剧集的来源不显示为播放候选。
- 换源弹层传入当前正片集号；目录全部是明确正片集号且确认缺集时隐藏该结果。无法解释的剧集名称不会被当作确认缺集，仍需人工选择。网络错误和验证码保留重试/验证入口。
- 目录缓存最长 5 分钟、最多 128 条，按作品 ID、来源 ID、规则版本和详情地址区分。刷新与手工修改关键词会作废对应缓存。单条搜索结果获取目录失败不阻断同来源其他结果。
- “自动优选来源”按近期解析、媒体打开到首帧的有效耗时和失败惩罚选择。无样本时保持配置顺序；不能据此宣称某规则恒定最快。成功播放后不会因另一来源更快而抢占。
- 每轮最多 3 个来源/线路候选，临时错误每候选最多追加重试一次；原生总预算 120 秒、Web 180 秒。连续 3 次失败的来源自动冷却 2 分钟，人工选择仍可尝试。
- 跨源只自动匹配唯一正片集号，保留真实线路/剧集索引；SP、OVA、合集、只有“正片”标题的电影不会套用集序号回退。人工指定来源保持固定，失败后显示重试入口。
- 媒体初始化失败、媒体错误和首帧等待超时均进入失败处理。首帧有效等待阈值为原生 15 秒、Web 25 秒；暂停和后台不累计，Web 未实际播放也不累计。开始播放后的媒体错误最多触发 2 轮自动恢复，防止无限循环。
- 人工切集、切源、退出作废旧会话；旧解析、旧媒体回调和旧初始化超时不能覆盖或停止新播放。手动重试使用当前实际进度；跨源先从头打开，仅在同集身份可靠、时长已知且差异不超过 10%（上限 30 秒、下限 5 秒）时恢复进度。
- 不新增依赖，不创建第二个播放器，不修改讨论、评价、资料接口，也不混入在线/离线回退。

## 自定义 HTTP 解析配置

规则编辑器高级区域可以填写 HTTP 解析 JSON；保存到 `sourceConfig.resolveApi`，请求复用 RuleEngine。搜索和剧集仍需配置现有 XPath / API 规则；只有解析接口不能凭空产生作品目录。

示例中的域名是占位符，请替换成自己的服务地址：

```json
{
  "request": {
    "method": "POST",
    "url": "https://resolver.example/resolve",
    "headers": {"Content-Type": "application/json"},
    "bodyType": "json",
    "body": {"url": "@episodeUrl"}
  },
  "urlPath": "$.data.url",
  "headersPath": "$.data.headers",
  "formatPath": "$.data.format",
  "expiresAtPath": "$.data.expiresAt"
}
```

对应响应：

```json
{
  "data": {
    "url": "https://media.example/video.m3u8",
    "headers": {"Referer": "https://site.example/"},
    "format": "hls",
    "expiresAt": "2027-01-01T00:00:00Z"
  }
}
```

支持 GET / POST、已有查询参数/请求头/JSON 或表单模板以及受限 JSONPath。媒体 URL 必须是 HTTP(S)，`expiresAt` 使用可解析的 ISO 日期字符串；过期地址拒绝播放。播放请求头同时传入播放器和下载流程，凭据不进入公共性能样本。没有配置 resolveApi 时仍使用媒体直链或原有平台网页解析。

原生、Web 的实际请求能力不同。Web / HTTP 服务沿用现有网关的地址限制，不会绕过安全网关请求 localhost、内网或任意端口；Web 任意媒体请求头仍受浏览器和现有媒体代理能力限制。

## HTTP 外观接口

- `GET /api/v1/sources?domain=anime` 或 `domain=screen`：返回分类、接入方式和 enabled。
- `GET /api/v1/search?q=关键词&domain=anime`：聚合时过滤禁用或领域不符来源。
- 指定来源的搜索/目录也校验领域参数和启停；来源信息、健康状态仍可查看。
- 既有会话、剧集、不透明媒体引用与解析任务接口继续保留；HTTP resolve 与直链解析不再强制走浏览器。
- 解析凭据保留在服务端；媒体引用遵守接口返回的有效期。HTTP 外观选择明确 providerId，跨源自动优选和媒体首帧恢复发生在应用播放控制器，不由 HTTP 服务自动初始化播放器。

命令入口：

```powershell
.\.tooling\flutter\bin\dart.bat run tool/source_api.dart --gateway http://127.0.0.1:8933 --rules C:/Users/haige/AppData/Roaming/com.example/kazumi/plugins/v2/plugins.json --port 8940
```

未传 `--rules` 时仍只加载内置规则；不会擅自读取其他平台的用户配置。可通过 `--policy <文件>` 显式加载本地覆盖。独立 HTTP 进程不实时跟随应用修改，不应让两个进程同时写同一个策略文件。本次没有启动新的 HTTP 服务。

## 修改文件与影响

| 文件 | 用途与影响 |
|---|---|
| `lib/services/source/source_profile.dart`、`source_policy.dart` | 领域、本地覆盖、有限性能记录与排序 |
| `lib/services/source/source_candidates.dart` | 作品匹配、有效目录缓存、同集映射和候选检索 |
| `lib/services/source/source_resolve_config.dart` | 自定义 HTTP 请求/响应契约与有效期校验 |
| `lib/services/source/source_models.dart`、`source_service.dart`、`source_playback_service.dart` | 统一来源 manifest、HTTP/直链/网页解析边界 |
| `lib/services/source/source_http_client.dart`、`source_http_server.dart`、`tool/source_api.dart` | HTTP 分类查询、禁用校验、媒体解析与策略入口 |
| `lib/services/plugin/rule_engine.dart`、`plugin_search_service.dart` | 复用 API 请求器、批次取消、人工查询优先和有效候选发布 |
| `lib/plugins/plugins.dart`、`plugins_controller.dart` | 旧 type 迁移、本地策略加载、验证码错误传播 |
| `lib/pages/plugin_editor/plugin_view_page.dart`、`plugin_editor_page.dart` | 分类、启停、HTTP 配置编辑与保留原 sourceConfig |
| `lib/pages/info/source_sheet.dart`、`source_sheet_view.dart` | 无资源隐藏、当前集筛选、优选/刷新/检索入口 |
| `lib/pages/video/video_playback_args.dart`、`video_controller.dart`、`playback_scaffold.dart` | 选择模式、有限恢复、取消、首帧与手动重试 |
| `lib/pages/player/controller/player_playback_controller.dart`、`lib/pages/player/player_controller.dart` | 当前媒体错误转发、暂停状态与独立播放生命周期 |
| `lib/presentation/modern/pages/modern_player_detail_page.dart` | 同集换源、提交时读取实时进度、时长保护 |
| `lib/services/video_source/video_source_service.dart`、`video_source_resolver_pool.dart`、`lib/pages/download/download_controller.dart` | HTTP 媒体结果和请求头复用于下载 |
| `openspec/changes/classify-and-schedule-playback-sources/`、相关设计/交付文档 | 契约、实现任务和验证边界 |

## 验证记录

- PASS：修改范围静态分析无错误、无警告；保留原有 `video_controller.dart` 的 1 条 `use_null_aware_elements` 信息提示。
- PASS：OpenSpec strict 验证没有问题。
- PASS：最终 Web 预览编译成功（`main_home_preview.dart`，输出 `build/modern-home-preview`，131.9 秒）；现有 8933 服务读取该目录。未操作页面交互。
- PASS：34 个交付文件严格 UTF-8 解码通过，无 BOM 或替换字符；27 个 Dart 文件格式检查无变化，`git diff --check` 通过。
- 未执行自动页面测试、真实站点批量测速或播放测试。Android / Windows 原生首帧、Web 请求头/CORS、真实验证码和外部算法服务均待人工验收；不能将静态分析或编译视为端到端通过。

## 手动验收

1. 规则管理检查动漫/影视/未分类及禁用开关；更新规则后本地设置仍在。
2. 动漫详情只检索动漫来源；影视详情不混入这些 16 条动漫规则。
3. 选源时无匹配、无有效目录、确认缺当前集的结果隐藏；错误与验证码保留操作入口。刷新可以重新检索。
4. 点击自动优选，检查临时失败后重试/换源及预算耗尽后的错误状态；人工指定来源失败时不自动抢占。
5. 快速切集、换源、返回页面，确认旧解析和旧首帧回调不会跳回旧集或停止新媒体。
6. 暂停或退后台超过首帧阈值，恢复后不因暂停时间误判。Web 关闭自动播放时需由用户点击播放。
7. 同一正片集换源尝试恢复实时进度；跨季、SP/OVA、歧义映射、时长明显不同必须人工确认或从头开始。
8. 用自己的 HTTP 接口检查模板、JSONPath、过期 URL、播放请求头和下载；验证 HTTP domain 筛选及禁用错误响应。

## 剩余边界与回滚

标题与明确集号匹配是保守回退，不能证明两个站点的剪辑完全一致。没有服务侧稳定作品 ID / 季年信息时仍可能存在同名歧义，应优先人工核对。当前实现没有做播放中持续缓冲超时、逐线路测速、跨同站共享速率限制或展开式诊断面板；这些属于可选后续工作。

回滚仅反向本次应用、OpenSpec 和文档差异；交付差异另存 `.dart_tool/classified-sources-delivery.patch`。应用代码回滚后旧 JSON 仍可导入；独立策略文件可以保留，旧版本不读取它。用户之前已有的页面修改不在本次回滚范围。
