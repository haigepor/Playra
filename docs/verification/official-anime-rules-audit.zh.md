# 官方动漫规则一致性与调度审查

日期：2026-10-12。项目：`C:/Users/haige/Desktop/Playra`。

## 结论与审查边界

**16 条内置规则全部来自当前官方目录，全部显式声明 `type: anime`。有效规则配置和搜索、剧集请求生成对比为 16/16 PASS。** 官方 XPath、JSON API 解析策略、配置模型，以及 Android、Windows 的视频解析和验证码 WebView 实现，均没有相对于本次官方基线的修改。

这个结论不等于“16 个站点现在都能播放”，也不等于“项目整体行为与官方完全相同”。本项目有分类、HTTP 外观接口、自动选源、首帧统计、有限重试、Web 网关等扩展。本次检查配置、源码和离线解析边界，没有访问全部站点进行搜索、验证码或视频播放，也没有安装 APK、执行页面 UI 测试。

本轮交付审查文档和本机诊断证据；应用代码、16 条规则 JSON、依赖和已有 APK 均未修改。

## 可复现的官方基线

通过 `git ls-remote` 核验远端 main，再按固定提交下载原始规则，避免比较过程中官方 main 变化：

- [官方规则仓库](https://github.com/Predidit/KazumiRules/tree/fce5e15a2e6b57500912d41b3f1c65bb3eb7d392)：`fce5e15a2e6b57500912d41b3f1c65bb3eb7d392`。
- [官方主程序](https://github.com/Predidit/Kazumi/tree/dc18be2af7636ae852cb49d0c4460e49b04b467c)：`dc18be2af7636ae852cb49d0c4460e49b04b467c`。本地 `upstream/main` 与该提交一致。
- 官方 `index.json` 恰好包含以下 16 条，与本地内置名单、版本一致。规则文件及目录均成功读取。
- GitHub REST commits 请求遇到匿名 API 限流；改用 Git 远端引用和固定提交的 raw 文件完成核验，没有用缓存结果代替当前远端事实。

## 16 条规则归档

| 规则 | 官方/本地版本 | 内容领域 | 搜索 / 剧集模式 | 站点 | 有效配置与请求 |
|---|---|---|---|---|---|
| 7sefun | 1.3 | 动漫 | XPath / XPath | www.7sefun.top | PASS |
| aafun | 1.2 | 动漫 | XPath / XPath | www.moonci.com | PASS |
| AGE | 1.5 | 动漫 | XPath / XPath | www.agedm.io | PASS |
| akianime | 1.4 | 动漫 | XPath / XPath | www.akianime.cc | PASS |
| baimao | 1.0 | 动漫 | XPath / XPath | www.baimaodm.com | PASS |
| dalvdm | 1.1 | 动漫 | XPath / XPath | www.sbdl.cc | PASS |
| DM84 | 1.4 | 动漫 | XPath / XPath | dmbus.cc | PASS |
| ezdmw | 1.2 | 动漫 | XPath / XPath | m.ezdmw.org | PASS |
| giriGiriLove | 2.4 | 动漫 | XPath / XPath | ani.girigirilove.com | PASS |
| mgnacg | 1.0 | 动漫 | XPath / XPath | www.mgnacg.com | PASS |
| moonci | 1.0 | 动漫 | XPath / XPath | www.moonci.com | PASS |
| mutefun | 1.2 | 动漫 | XPath / XPath | www.2kdm.com | PASS |
| MXdm | 2.4 | 动漫 | XPath / XPath | www.dcc3.com | PASS |
| sorani | 1.0 | 动漫 | JSON API / JSON API | www.sorani.net | PASS |
| xfdmneo | 1.1 | 动漫 | XPath / XPath | dm1.xfdm.pro | PASS |
| xfdmnext | 1.1 | 动漫 | JSON API / JSON API | next.xifanacg.com | PASS |

14 条 XPath 规则、2 条 JSON API 规则，共 15 个不同站点。`aafun` 和 `moonci` 虽然同域名，仍是官方保留的两个规则身份，不能仅因域名相同合并。`xfdmneo` 的 `useLegacyParser: true` 与官方一致，应继续保留。

原始 JSON 对象比较中，`dalvdm`、`moonci`、`sorani` 三条完全一致；其余 13 条只补写了官方反序列化时已存在的默认值，例如 `usePost: false`、`useLegacyParser: false`、`adBlocker: false`、XPath 模式、空 Referer 和验证码配置默认项。不存在站点地址、XPath、JSONPath、API 请求模板、实际验证码参数或版本的改写。

对照官方 `Plugin.fromJson`、`AntiCrawlerConfig.fromJson` 默认语义后，使用项目实际 `SourceDefinition`、`ApiSearchConfig`、`ApiChapterConfig`、`AntiCrawlerConfig` 比较有效配置，并通过实际请求策略分别生成“吞噬星空”搜索请求与相同作品引用的剧集请求；16 条均一致。无需为了消除等价默认项重新覆盖用户规则。

## 哪些逻辑应继续以官方为准

1. `RuleEngine` 是执行入口；XPath 与 JSON API 按规则明确声明分派。API 规则不能强制交给 XPath，也不能把站点播放页面当成最终媒体地址。
2. 保留官方的 URL 规范化、关键词编码、GET/POST、JSON/表单模板、受限 JSONPath 和实际线路/剧集返回顺序。页面的升降序仅改变展示，播放仍使用原始索引。
3. 保留官方 Cookie 和验证码语义：搜索及 API 请求按配置携带 Cookie；XPath 剧集请求沿用官方不携带该 Cookie 的行为。验证 Cookie 对应的 User-Agent 必须配套使用，不能为了“统一”强行改变。
4. 原生解析继续走官方平台 WebView，并保留 `useLegacyParser`。项目的 Flutter 请求执行器从官方 RuleEngine 中提取，实际请求头优先级、Cookie、已验证 User-Agent 和内容类型处理保持一致。
5. 内容领域以显式规则声明为依据。这 16 条仅参与动漫作品候选；以后影视和自定义 API 应另外声明领域。解析成功、加载首帧快，都不能成为把动漫规则提升为“全领域来源”的理由。
6. 官方规则版本/API 级别检查、禁止降级、串行持久化、现有来源 ID 与用户启停/领域策略继续保留。16 条内置规则在新设备补齐时，不覆盖已有同名/同身份自定义规则。

本项目把缺失 `type` 的自定义规则视为 `unknown`，官方则默认 `anime`。这是为避免未知规则误进入动漫/影视候选的明确项目扩展；16 条官方规则均有显式 `anime`，因此不受影响。Web 解析与独立 HTTP 请求器是项目扩展，不能据原生源码一致就宣称 Web 会话、验证码或解析速度与官方相同。

## 当前自动和人工流程

自动流程为：按领域和启停筛选 → 按历史首帧评分排序 → 最多 4 个检索 worker → 作品名称/中文名/已知别名匹配 → 获取非空目录 → 明确同集匹配 → 交给同一个播放器解析。首个准备好的可靠同集候选即可进入播放，不等待所有来源结束。

`SourcePolicy` 使用最近 7 天、最多 12 条记录，按成功首帧平均耗时、失败比例和样本不足惩罚评分；连续 3 次失败后冷却 2 分钟。当前实现是历史表现优先和较快候选先就绪，**没有同时测量全部来源的当前视频首帧，所以不能保证每次选到绝对最快来源**。

自动播放每个候选对可重试错误最多解析 2 次，最多尝试 3 个候选，原生/Web 调度预算分别为 120/180 秒。媒体错误最多触发 2 轮恢复。切集、人工换源和退出会取消旧会话，避免旧回调覆盖新播放。跨源恢复进度有同集、时长校验。

人工选择保持固定来源；媒体失败显示重试/换源入口，人工重试使用实际进度，单次解析不会悄悄改成自动换源。这个区别应保留。自动调度的重试策略属于项目扩展，官方解析器不应承载这些调度决策。

## 已确认的问题与优化顺序

### P1：补写标签不能充当跨源集号证据

官方 XPath 和 JSON API 策略都会在剧集名称为空时补写 `第N集`，N 来自节点位置。当前 `regularEpisodeNumber`、`episodeMatches` 和 `confirmsMissingEpisode` 无法区分站点真实名称与这种补写名称。

已运行离线边界样例：两个无名称链接 `/play-12`、`/play-11` 被官方一致的 XPath 策略显示为 `第1集`、`第2集`；当前匹配正则会把第一条当作第 1 集。这证明位置标签会被误认成集号，**不证明全部 16 个站点的实际目录都有这个问题**。

优化应保留官方显示标签和解析顺序，在转换/调度层附加 `episodeIdentityEvidence`，区分 `source_label`、`api_id`、`position_fallback` 和 `unknown`。只有可靠证据可自动跨源映射、恢复进度或确认某集缺失；补写标签仍可人工播放。该证据须贯穿 Road/来源目录转换、缓存和播放上下文，不能在页面中凭字符串临时猜测。

### P1：未匹配作品不等于站点无资源

`SourceCandidates.prepare` 在自动检索时跳过所有不精确匹配的标题；`PluginSearchService._publishPrepared` 又把空候选标为 `noResult`，选源列表随后隐藏该来源。因此，站点返回了相关作品但名称带前缀/不同译名/别名尚未加载时，可能被误判为无资源，甚至没有发起剧集请求。

应增加 `unmatched` 或 `needs_confirmation` 状态，允许人工查看官方搜索结果或换关键词；只有真正空搜索结果、成功获取空目录或可靠同集缺失才隐藏。网络失败、验证码、标题不确定和取消分别处理。自动流程保持严格匹配，不为了展示结果而放松自动播放的同作品要求。

### P1：官方更新可能覆盖自定义 HTTP 接入

`PluginsController._replacePlugin` 目前保留旧 `sourceId`，却直接用新规则替换对象，没有保留旧 `sourceConfig`。对官方规则添加本地 `resolveApi`、目录适配器等扩展后，后续官方升级可能使这些配置丢失。独立策略文件里的 enabled/domains 不受此问题影响。

应区分“官方更新”与“人工导入/编辑”路径：官方更新更新官方字段，保留明确归属本地的扩展；人工编辑允许真正删除扩展。不能在通用替换方法里无条件合并旧配置，否则用户无法移除自己设置的解析接口。长期可把扩展也迁入以 providerId 为键的本地覆盖，继续兼容旧 JSON 导入导出。

### P2：缓存应跟随执行配置和验证状态失效

候选缓存为 5 分钟、最多 128 条，键主要是作品 ID、providerId、版本和作品引用。手工改变同版本的 URL/选择器/API 模板，或验证后 Cookie/UA 变化时，不会自动改变这个键。现有人工刷新有主动失效，但不足以覆盖所有规则编辑和验证路径。

应增加有效执行配置指纹及会话/验证代次；别名或领域改变后重新计算匹配结论。继续不缓存临时媒体 URL/解析凭据到公共统计。更换来源后必须重新核对集号，不能利用过期目录推断。

### P2：自动检索保留失败原因并增量恢复

`SourceCandidates.discover` 捕获单源错误后继续其他来源，这能避免单源阻断，但没有给调用方返回每个来源的失败/验证状态。手动选源界面已有 error/captcha 状态，应复用到自动结果摘要；自动找不到来源时提供有依据的“需验证/检索失败/无匹配”，不要统一报没有资源。

初次自动选集可增量接受候选；播放失败后的补检索仍会等待 `discover` 的完整结果。应在同集候选就绪时允许恢复，不必等所有慢源结束，并保留剩余预算和旧会话失效检查。

### P2：优化速度评分和同站点并发

当前成功耗时使用算术平均，并非加权平均或当前实时测速。可改为近期权重/稳健分位数，同时展示样本数、测量时间和环境；空样本采用稳定的配置顺序作为平分时的排序依据。保留首次画面成功指标，不能只按搜索接口响应速度宣称“最快播放源”。

检索目前只有单个调用的 4 worker 限制，未见全局的按域名配额；自动、人工和其他调用可能同时请求同一站点。应对同域名限制 1—2 个在途检索、共享短时请求结果，但保留 `aafun`/`moonci` 的独立规则配置、身份和健康信息。不要同时启动 16 个媒体播放器测速。

## 后续验收契约

- 官方规则更新：名单/版本/有效配置可对照，XPath/API 路径不变，原生默认解析与 `xfdmneo` 兼容模式保留。
- 目录身份：正序、倒序、缺集、重复集号、合并季、特别篇、空名称均不能依赖展示位置跨源播放；排序保持真实索引。
- 状态展示：真实空结果可隐藏，标题不确定/验证码/超时可重试或人工确认；取消不计为来源故障。
- 更新与缓存：本地扩展不被官方更新覆盖，人工可删除扩展，同版本编辑和验证后的缓存失效。
- 调度：候选逐步就绪、预算有限、人工优先、旧会话不能写回；首帧统计和测速说明可核验。
- Android、Windows、Web 分开验证。HTTP API 的目录/解析能力与应用播放器首帧恢复能力分别报告，不混为同一能力。

## 证据、状态与文件影响

本机诊断目录：`.dart_tool/official-rules-audit-20261012/`，包含固定版本官方 JSON、官方 index、原始字段差异、`semantic-comparison.json` 和离线比较脚本 `compare.dart`。这里是被 Git 忽略的诊断产物，不是新增运行时依赖。

实际执行成功的比较命令：

```powershell
.\.tooling\flutter\bin\cache\dart-sdk\bin\dart.exe --packages=.dart_tool/package_config.json .dart_tool/official-rules-audit-20261012/compare.dart
```

普通 `dart run` 首次触发全项目 media_kit 原生构建 hook，因本机 vswhere 输出解码出现 `FormatException: Control character in string` 而失败。比较本身不需要媒体库，随后使用显式 package config 直接执行 Dart 脚本成功；没有更改依赖、系统编码或构建配置。该 Windows hook 问题不代表规则兼容性失败，也不作为 Android 打包结论。

| 项目 | 状态 | 说明 |
|---|---|---|
| 官方 main 提交与 index 核验 | PASS | Git 远端引用、固定提交原始文件 |
| 16 条有效配置 | PASS | 使用实际配置类正规化，16/16 |
| 16 条搜索/剧集请求生成 | PASS | 实际 XPath/API 请求策略，16/16 |
| 官方核心策略/模型、Android/Windows WebView 源码一致 | PASS | `git diff upstream/main` 指定文件为空 |
| 缺名剧集身份风险 | 已复现 | 离线执行实际 XPath 解析器 |
| 自动调度与来源状态完善程度 | PARTIAL | 上述 P1/P2 已定位，本轮未实施 |
| 16 站点实际搜索/验证/首帧 | NEXT | 需要按平台、当前网络和真实作品分别验证 |

新增文件仅为 `docs/verification/official-anime-rules-audit.zh.md`，用途是记录当前官方对照与待完善的调度边界；不影响应用运行或已有安装包。回退本轮文档只需移除此新增文件；已有工作区修改均保留。
