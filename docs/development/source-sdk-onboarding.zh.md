# 内容 SDK 与接口接入规范

更新：2026-10-14。适用范围：Playra 新增内容 SDK、影视 HTTP API、动漫规则和资料来源。本文是后续接入的执行入口；历史分析记录用于理解原因，接口签名以当前源码为准。每次接入复制[接入记录模板](templates/source-sdk-checklist.zh.md)，完成后随代码提交。

## 1. 先确定接入路径

| 来源形态 | 使用路径 | 不应新增的东西 |
|---|---|---|
| 动漫站点 HTML / 可配置 JSON API | 现有 `Plugin`、`SourceService`、`RuleEngine`、`RuleContentProvider` | 不复制搜索页面、验证码或播放器 |
| 影视 SDK / 需要专用协议的影视 API | 专属 Service/Adapter + `ContentSearchProvider` + `SdkPlaybackProvider` | 不复制 Mio 页面，不让公共页面判断 SDK 类名 |
| 仅搜索资料、没有播放能力 | `ContentSearchProvider`，`canPlay=false` | 不显示成可播放 SDK，不伪造线路或空播放地址 |
| 需要 Python 签名、解密等算法 | 上述业务 Adapter + 受限运行时传输 | 不允许客户端上传脚本、指定任意网络目标 |

纯 HTTP API 也可实现 `SdkPlaybackProvider`；这里的 SDK 表示统一播放来源能力，不要求供应商必须发布一个 SDK 包。只有真实实现的来源进入执行集合；预留结构不等于展示可点击的虚假来源。

现有 `RuleContentProvider` 虽然提供规则播放能力，但没有 `sdkPlayback`。仅把规则 `contentGroups` 改成 `screen/series` 不会获得非动漫 SDK 播放入口；需要用统一播放 Adapter 适配其能力并补全入口测试。

目前通用 SDK 页主要覆盖影视、漫剧和剧集。动漫仍复用 Bangumi 资料与规则播放链路；要把新的动漫 SDK 纳入通用页，先明确资料身份和路由策略并补回归，不能只加枚举就宣称支持。首页推荐/榜单当前也有 Mio 专项调用；注册通用搜索来源不会自动生成新 SDK 的首页目录。

## 2. 固定术语与分类

```text
作品 ContentWork
  → 播放源 provider：miomedia / 后续 SDK
    → 来源作品 contentId
      → 当前作品的线路 lineCode
        → 当前线路的真实剧集 episode
          → 可用画质 quality
            → 已解析媒体 media
```

| 展示分类 | 代码 | 归属 |
|---|---|---|
| 动漫 | `ContentGroup.anime` | 动画作品；当前规则与 Bangumi 链路 |
| 影视 | `ContentGroup.screen` | 电影、综艺、纪录片 |
| 漫剧 | `ContentGroup.comicDrama` | 漫剧 |
| 剧集 | `ContentGroup.series` | 全部真人连续剧，含国产、港台、日韩、欧美及真人短剧 |

地区是筛选条件，不能再把日剧、美剧、韩剧做成互相割裂的播放系统。上游分类有歧义时，Adapter 记录映射证据并保留未知状态，不能仅凭名字猜作品类别。

| 标识 | 规则 |
|---|---|
| `providerId` | 稳定唯一、不随显示名改变；搜索与播放提供方必须一致；运行时路由 ID 还须满足其 1–64 位字母/数字/下划线/连字符约束 |
| `contentId` | 来源内部字符串 ID；保留大整数、路径等原值，不能转成其他 SDK 或 Bangumi 的 ID |
| `lineCode` | 来源详情返回的真实代码，保留大小写；按作品动态读取，不全局硬编码线路总数 |
| `SdkEpisode.number` | 当前契约为整数真实编号，可能是 12、42、914；不能使用按钮序号或列表索引代替 |
| `quality.code` | 供应商真实画质码；显示名与排序证据分开保存 |

如果新接口只有字符串剧集 ID，不能把数组下标或不稳定 hash 冒充真实编号。先设计稳定映射，或同步升级剧集契约及所有调用者、身份校验和测试，再接入。

## 3. 搜索与去重契约

实现 [ContentSearchProvider](../../lib/services/source/content_search.dart) 的 `id/name/groups/search`；可播放 SDK 同时提供 `canPlay=true` 和 `sdkPlayback`。在 [contentProviders()](../../lib/services/source/content_providers.dart) 登记一次，明确谁持有并释放 Service。

`search(ContentQuery, page, CancelToken)` 返回 `ContentSearchPage(items, hasMore)`。每个 `ContentHit` 至少保存 `providerId/contentId/title/group`，能取得时补充 `year/edition/metadataId/aliases/region/cover`；缺失年份保持空值，不能用当前年份补齐。

统一会话的默认行为：同时发起全部选中来源，谁先完成谁先展示；单来源失败不阻止其他来源，单来源默认 20 秒、批次默认 35 秒。除非上游确有限流要求，不在 Adapter 内额外排一条跨来源全局串行队列。翻页沿用上游页码及 `hasMore`，未知页数不能伪造无限下一页。

去重交给公共 `matchContent/ContentWork`：

1. 同一 `providerId + contentId` 是同一来源条目。
2. 年份、分类或明确版本冲突时不合并；资料 ID 冲突时不合并。
3. 身份明确，或规范化片名/别名、分类、年份证据充分时聚合为一个作品，其命中保留为不同播放源。
4. 只有同名、资料稀疏的结果保留为候选，不能为了减少卡片而合并错片。
5. 同一 SDK 聚合到多个不同作品 ID 时，当前入口不会随机选第一条；先消除歧义或补明确选择设计。

## 4. 实现统一播放 Adapter

复用 [SdkPlaybackProvider](../../lib/services/source/sdk_playback_provider.dart)，参考 [MioSdkPlaybackProvider](../../lib/services/source/miomedia/miomedia_playback_provider.dart)。供应商协议只放在自身目录，例如 `lib/services/source/<provider>/`。

| 成员 | 返回 / 行为 | 验收要求 |
|---|---|---|
| `id/name` | 稳定身份与产品显示名 | 当前 Mio 显示名为小写 `miomedia` |
| `detail(id, cancel)` | `SdkVideo` / `SdkVideoData`，含动态 `lines` | 返回同一来源作品，线路代码去重，不给每部作品硬挂全部历史线路 |
| `episodes(id, code, cancel)` | `List<SdkEpisode>` | 保留真实编号、名称、顺序、所属代码及特殊集 |
| `supportsQualities` | 默认 false | 没有画质查询能力时不要伪造能力 |
| `qualities(id, code, episode, cancel)` | `List<SdkQuality>`；默认空 | 仅包含公开画质码/名称/尺寸证据，不带交换令牌 |
| `play(id, code, episode, quality, cancel)` | 标准媒体结果 | 执行当前明确选择，保留必要媒体请求头，支持取消与超时 |

成功响应形状示例，值均为说明用途：

```json
{
  "status": "ready",
  "selection": {
    "videoId": "source-content-id",
    "code": "real-line-code",
    "episodeNum": 914
  },
  "media": {
    "url": "https://media.example/video.m3u8",
    "format": "m3u8",
    "headers": {"Referer": "https://source.example/"}
  }
}
```

`selection` 必须回显这次请求的来源作品、线路、真实剧集编号；协调器不接受混入其他来源的资源。地址必须是有效 HTTP(S) 媒体地址，不得返回解析中间页冒充视频。失败返回稳定公开状态/错误码，例如 `unavailable`；需要供应商验证则使用 `ad_required` 或受控的验证流程，不能假装播放成功。

`SdkPlaybackEntry.fromWork()` 负责从真实搜索命中构造来源列表，`/info/` 使用共享 `SdkDetailPage`。新增 SDK 不应在页面里出现 `if (provider is NewSdk)`，也不应再增加一个独立播放器页面。

## 5. 选线、画质与换集规则

公共 [SdkPlaybackCoordinator](../../lib/services/source/sdk_playback_coordinator.dart) 负责策略，Adapter 只执行协议：

- 首次进入即加载详情、目录并自动解析起播，不加作品确认弹窗，也不等用户再点播放才加载目录。
- 目录/画质按最多 3 路并发读取，整体默认 10 秒截止；已经匹配的目录不能因画质超时丢失，超时也不能展示为“没有资源”。
- 画质有证据时从高到低选择，同档按本平台起播成功记录与耗时排序；失败先试同档其他线路，再尝试低档。未知画质保持未知。
- 播放换取和媒体打开串行，只有一个活动播放器；不能并发消费所有线路的 token、nonce 或凭证。当前播放尝试总预算为 75 秒，媒体首帧等待最多 25 秒。单次 HTTP/运行时还各有自己的预算，不能把 75 秒误当作每个请求都可等待 75 秒。
- 只有实际起播/首帧成立才记为播放成功。目录非空、HTTP 200、取得 URL 或解码器初始化均不是完整播放验收。
- 手动选线立即匹配当前集并解析播放，保持手动锁定；不跨 SDK 静默回退。无对应集时清楚提示，不能偷播第 1 集。
- 普通集数允许语义规范化；特辑、日期集等优先完整唯一匹配。电影跨名称匹配要求电影属性及双方单条目录证据。
- 所有异步响应检查取消和选择代次，迟到的首条目录、旧画质、旧解析、旧播放器事件不得覆盖用户新选择。
- 换线准备期间保留原媒体，新地址就绪再替换；仅在时长等兼容证据成立时交接进度，不承诺不同剪辑的时间轴完全一致。

线路名“蓝光超清+”不等于 4K，`qualities[0]` 不等于最高。解析输出与 SDK 档位名称不同，不应拒绝仍然合法的媒体；保留降级/未知证据。当前 Mio 的多档标准化实现见 [miomedia_quality.py](../../tool/source_runtime/miomedia_quality.py)。

SDK 声明和实际解码分开显示：前者标“来源声明”；后者显示 `1920×800 · 实际分辨率`。宽银幕裁黑边不能直接用高度判定为低画质；尺寸也不等同码率或观感。没有全部线路的真实证据时，不宣称已验证绝对最高画质。

## 6. 传输与平台接入是另一道门

通用 Flutter 接口已建立，底层运行时目前仍存在 **Mio 专用入口**。新增 SDK 不能直接调用 `callMioMedia`，也不能只在 Python `registered_adapters()` 注册后就宣称全端接通。

| 平台 / 层 | 当前实现位置 | 新 SDK 需要核对 |
|---|---|---|
| Dart 传输 | `lib/services/source/runtime/source_runtime.dart` 与供应商 Service | 选择直接受控 HTTP 或扩展运行时调用，不能借用 Mio 协议/身份 |
| Python | `tool/source_runtime/adapters.py`、`server.py` | 通用 `search/episodes/resolve` 可按能力注册；`sdk` 当前仅允许 miomedia，扩展需显式路由、参数校验和测试 |
| Web 固定桥 | `tool/web_backend/runtime.cjs` | 新 SDK 操作必须在受控白名单内，保持同源、请求上限、取消与超时；不开放任意代理 |
| Android 内置 Python | `tool/source_runtime/android_bridge.py`、`android/app/build.gradle` | 当前 SDK 分支为 Mio 专用；新增分发和私有目录隔离，新模块加入显式随包列表，核验 APK 实际包含依赖 |
| Android 播放 | `PlayerController/PlayerItem` | 复用动漫一致的原生播放器、硬解和缓存设置，不退回网页 iframe |
| Web 播放 | `SourceMediaPlayer`、media_kit/ArtPlayer | 复用媒体所有权、请求头/媒体网关；切源后仍只有一个 video，无晚到自动播放 |
| iOS / 桌面 | 公共页面 + 配置的 HTTPS 运行服务 | 当前没有 Android 的内置 Python 能力；分别验证服务可达和实际播放，页面共用不代表桥接已完成 |

私有 SDK、设备身份、令牌、证书和签名配置作为私有构建输入管理，不提交 vendor 内容或私有数据。不同 SDK 使用独立会话与存储命名空间，不共用设备密钥。对媒体确实需要的请求头按来源受控传递，避免跨主机泄漏 Cookie/Authorization；日志只记录公开错误、时间、身份引用与必要的脱敏信息。

详见[算法运行时](../source-algorithm-runtime.zh.md)、[构建输入](../release/build-inputs.zh.md)及[平台构建](../release/build-platforms.zh.md)。本地 Python 开发服务器不是可直接公网发布的生产服务。

## 7. 样式与交互复用

沿用 `modernHomeTheme` 的语义 token 和共享来源卡片/线路面板；SVG 使用主题着色，装饰不截获触摸、不进入读屏。选中、自动模式与当前实际线路的状态不能混淆；关闭按钮必须有可见颜色和读屏名称。

动效用于说明切换，遵守 `MediaQuery.disableAnimationsOf`；不加影响播放和滚动的无限循环动画。至少检查 320 像素宽、2 倍文字、横屏、很多线路及长片名；无横向溢出，所有线路可滚动访问。

## 8. 接入实施顺序与交付门槛

1. **调查**：列接口/能力、真实字段、分类/版本、鉴权、限流、平台运行要求与成功/失败样本；不在日志保存私密值。
2. **映射**：确定身份、分类、剧集与画质转换；填模板中的契约表，列出不支持能力。
3. **最小闭环**：先单来源完成搜索→详情→真实目录→解析→已有播放器首帧，再登记聚合；实现去重/取消/超时。
4. **全线路**：动态目录、跨线路同集匹配、最高已知档优先、手动锁定和失败状态；不改 SDK 加密算法来绕过集成问题。
5. **平台**：核对上述传输表、打包白名单及依赖；使用正式页面入口，测试实际包而不只测试开发模式。
6. **验收**：运行项目门禁及专项故障测试；记录真实作品、线路、集数、设备、起播/切线结果，失败保留原因。
7. **交付**：更新来源清单、能力矩阵、接入记录和构建收据；记录源码版本、签名状态与回退方式。编译、接口、起播和持续播放分开下结论。

Windows 从仓库根目录使用项目 Flutter 工具链；同一 checkout 的 analyze/test/build 串行运行：

```powershell
.tooling/flutter/bin/flutter.bat analyze --no-pub --no-fatal-infos
.tooling/flutter/bin/flutter.bat test --no-pub
python -B -X utf8 -m unittest discover -s tool/source_runtime -p 'test_*.py'
node --test tool/web_backend/runtime.test.cjs tool/web_backend/artplayer_bridge.test.cjs
```

专项测试至少覆盖：两种不同 SDK 身份与编码；歧义作品不乱选；慢首来源不阻塞其他搜索；目录与画质并发；画质超时仍保留目录；多档顺序颠倒；未知画质；最高档失败降级；手动不自动跳线；真实集数 914 等非连续编号；旧响应晚到；解析/打开总预算；取消后不晚起播；缺失依赖和空目录。

真实链路至少选单线路电影、多线路电影和多集剧集，各验证自动起播、手动切线、换集、进度、拖动及失败重试。Android 实际播放器与 Web 实际 video 均需证据；iOS 未测应标明未测。

结果统一使用 **PASS / PARTIAL / FAIL / BLOCKED**，分别代表通过、部分通过、失败、外部条件阻塞。使用“已接入”只表示存在调用实现，不能代替所有服务当天在线、所有线路可播或所有端点已实测。

本轮参考：[SDK 实施记录](../analysis/sdk-provider-lines-quality-implementation-20261014.zh.md)、[SDK 入口测试](../../test/sdk_playback_entry_test.dart)、[协调器测试](../../test/sdk_playback_coordinator_test.dart)、[UI 测试](../../test/miomedia_sdk_ui_test.dart)。
