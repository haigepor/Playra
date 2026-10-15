# 动漫 / 影视播放源分组与交互统一分析

日期：2026-10-15；源码基线：37501c88及当前未提交实现。范围：分析与实施设计，本轮不修改播放业务代码。当前行为来自源码及既有测试审阅；没有把未执行的测试记为通过。

用户已确认：**顶层按 SDK 分组，动漫显示 AniFive，下面列 DM84 / MXdm / akianime / moonci 及各自线路，与影视的 SDK→线路逻辑一致。**

## 1. 结论与目标结构

当前不是简单样式差异。影视已经有“播放源SDK / 线路选择”两层UI；动漫仍是“当前站点 / 检索结果弹层 / 选集内切线路”。需要增加SDK分组及带范围的选线会话，再复用公共展示组件；不能只将DM84文字替换成AniFive。

目标在产品上保持两层展示，在数据上保留完整站点身份：

```text
播放源
  [ AniFive ]   [ 后续支持该动漫的 SDK ]

播放线路
  自动 · MXdm / 线路 1                         N 条可用线路 ›
  已知媒体尺寸 / 实际分辨率（有证据才显示）

线路弹层：AniFive · 播放线路
  ✓ 自动（优选线路）
  DM84       线路 1              待检测 / 可用 / 缺少当前集
  MXdm       线路 1              当前使用
  akianime   线路 2              可用
  moonci     线路 1              检测失败，可重试
  ……仅展示这部作品实际返回的目录，不固定线路总数

选集
  当前线路真实目录、当前集、排序/分段/已缓存标记
```

上述“线路1”仅为展示示例，不表示四源各只有一条。弹层按站点分组，点实际线路可直接切换；页面摘要合并显示“MXdm / 线路1”，不用再增加一层必须点开的站点选择。

影视维持顶层 `miomedia` 等SDK，下面是其真实线路。只展示支持当前内容、已启用的SDK；不能因为Mio底层manifest出现anime就将其当前未公开的动漫业务入口直接放出来。

## 2. 当前实现对照

| 维度 | 动漫 | 影视 / 通用SDK | 统一要求 |
|---|---|---|---|
| 页面 | `ModernPlayerDetailPage` | `SdkDetailPage` | 共用来源面板；保留各自业务上下文 |
| 顶层来源 | 当前 `Plugin.name`，例如MXdm | `SdkSourceBinding.provider.name`，例如miomedia | 按SDK显示，站点下沉到线路列表 |
| 页面位置 | 来源/线路位于选集标题下面，尚未播放时显示智能选源块 | 播放源和线路卡片位于选集前 | 稳定放在资料操作之后、选集之前；起播前后不更换整块结构 |
| 换源入口 | 打开SourceSheet重新检索；展示作品命中结果 | SDK ChoiceChip直接切换 | 常规选择直接操作已确认候选；检索诊断保留为更多操作 |
| 线路入口 | `allEpisodes`→`PlayerEpisodesSheet`的下拉框 | 独立播放线路卡片与弹层 | 独立线路弹层，选集面板主要负责选集 |
| 自动范围 | `automaticSource=true`可跨站点回退，没有SDK范围 | `automatic=true`只在当前service的动态lines内回退 | 自动仅在选中的SDK内；不跨SDK静默跳转 |
| 自动显示 | 起播后主要显示站点名，未显示完整自动模式状态 | “自动·当前线路”，弹层分别标自动选择和当前使用 | 明确自动模式、手动锁定、准备中与实际播放线路 |
| 手动锁定 | SourceSheet手选通常为false，但选集下拉换road不显式改自动标志 | selectLine设置automatic=false | 任何显式选线路动作都进入手动锁定 |
| 当前集匹配 | 同作品/正片集号或唯一URL匹配；不确定时要求选目标集 | 同SDK线路切换有匹配，跨SDK会清空_requestedEpisode | 同集匹配优先；无对应集不自动播首集 |
| 画质 | 四源没有统一可选档位协议；当前无公共画质探测能力 | supportsQualities+真实档位优先，再按历史表现 | 共享“自动优选”概念；只有有证据的SDK显示最高已知画质 |
| 换线时旧媒体 | switchOnlineSource先stop，再解析 | 新地址准备期间保留旧媒体 | 先准备候选，失败保留原播放；成功提交时切换并绑定正确历史身份 |

关键代码：

- [动漫来源行](../../lib/presentation/modern/pages/modern_player_detail_page.dart#L850)、[动漫选源](../../lib/presentation/modern/pages/modern_player_detail_page.dart#L375)、[动漫选集入口](../../lib/presentation/modern/pages/modern_player_detail_page.dart#L483)。
- [影视来源控件](../../lib/presentation/modern/pages/sdk_player_detail_page.dart#L516)、[影视线路弹层](../../lib/presentation/modern/pages/sdk_player_detail_page.dart#L679)、[手动选线路](../../lib/presentation/modern/pages/sdk_player_detail_page.dart#L182)、[跨SDK切源](../../lib/presentation/modern/pages/sdk_player_detail_page.dart#L220)。
- [动漫自动回退](../../lib/pages/video/video_controller.dart#L551)、[动漫换源提交](../../lib/pages/video/video_controller.dart#L684)、[来源候选](../../lib/services/source/source_candidates.dart#L265)。

## 3. 已确认的问题与优先级

### P1：缺少SDK分组身份，不能仅改显示名

目前四个Plugin分别拥有独立providerId，`SourceProfile`没有sdkId/groupId；`SdkSourceBinding`也只有provider/contentId/seed，没有单独的SDK家族层。AniFive是SDK家族，dm84/mxdm等是具体来源，二者不是同一个身份。

如果将四个sourceId都改为anifive，会破坏缓存、策略、历史和自定义规则区分；若只把当前名称写成AniFive，则四站点和实际播放线路又不可见。

建议增加维护者登记的分组元数据：`sdkId=anifive`、`sdkName=AniFive`，成员仍绑定各自providerId。对当前四源通过受管标识+固定adapter路由确认归组，不按显示名或域名包含关系猜。未声明SDK的旧自定义规则保持独立来源，不强行归入AniFive。

### P1：自动范围与手动锁定不完整

动漫 `automaticSource` 只有布尔值；回退时从插件总列表发现候选，没有“当前SDK”限制。当前页面来源摘要没有显示这一范围。从PlayerEpisodesSheet换road后直接调用changeEpisode，并未显式关掉原自动模式，失败时仍可能跨站回退。

需要将选择状态显式表示为 `sdkId + mode(auto/manual) + selectedRoute + activeRoute`。在AniFive自动模式内可以跨其四个站点，手动选择“MXdm / 线路1”后只重试这一条；要重新回退其他线路须用户切回自动。后续其他动漫SDK也遵守相同规则。

### P1：影视的跨SDK切源会丢失当前集，不能直接照搬

当前switchSource将_requestedEpisode置空，随后loadDetail(forceAutoPlay:true)从新目录首集开始。应作为共享面板接入的同步修正项：保存当前作品/剧集语义，匹配新SDK对应集，无法唯一匹配则提示选集；不重用其他SDK的裸ID或旧数组下标。

### P2：未知画质不能标“最高画质”

影视当前弹层标题是“自动（最高画质）”，因为它有qualities契约；AniFive四源只有解析/媒体验证，没有统一可选画质列表。对动漫照抄该文案会作出无证据承诺。

公共组件使用可配置策略文案：AniFive“自动（优选线路）”；有真实画质证据的来源说明“按最高已知画质优先”。实际解码尺寸单独标“实际分辨率”，不将站点名、清晰度营销名或HTTP200当成画质证据。

### P2：选择目标与正在播放未充分分离

影视onAttempt阶段就更新line；动漫切源也在首帧前安装当前Plugin。因此直接拿line/currentPlugin作为“当前播放”可能把待切目标标为正在使用。

共享面板应分清：用户选中、准备中的目标、实际起播路线。原媒体仍播放时展示“正在切换至…，当前播放…”，首帧成立后更新activeRoute；失败保留原媒体和activeRoute，同时显示目标失败状态。

### P2：规则Road缺少稳定线路码

`Road`目前只有name/data/identifier，SourceService线路ID是详情引用加数组位置，不能充当跨刷新持久线路身份。C源公开“线路2”，但UI中的road下标可能为0；把下标用于实际解析会错误调用。

统一模型需要保留原始站点/线路码或稳定引用。可为SDK响应与规则Road增加兼容的可选线路ID映射，缺失时仅将下标当本次已加载目录的视图定位，绝不作为持久化协议ID。剧集最终仍使用真实episodePageUrl解析和恢复。

## 4. 建议的共享边界

建议新增以下概念，名称为设计建议，当前源码尚不存在：

| 概念 | 承担职责 | 必须保留的身份 |
|---|---|---|
| PlaybackSourceGroup | SDK显示名称、图标、支持内容、成员映射 | sdkId |
| PlaybackRouteRef | 一条可操作的真实线路，不使用拼接字符串做协议解析 | sdkId/providerId/contentRef/真实roadCode或稳定引用 |
| PlaybackSourceSession | 当前作品的发现、目录缓存、选择、取消和状态发布 | 作品身份、目标集、选择代次 |
| PlaybackSourcePanel / LineSheet | 两页共用顶层SDK标签、线路摘要、状态与弹层 | 通过模型与回调消费，不判断Mio/AniFive类名 |

数据上是“SDK→站点→站点线路→真实剧集”，UI显示为“SDK标签→按站点分组的线路弹层”。动漫的Plugin、SourceCandidates、真实Bangumi身份继续负责协议和作品匹配；影视继续用SdkPlaybackProvider及协调器，不将动漫硬塞进仅支持整数集号的通用SdkEpisode模型。

优先抽取现有SdkSourceGlyph、SdkLineOption及来源面板的展示职责；用动漫会话适配器提供同结构的线路视图与动作。协议执行和历史写入仍通过原消费边界。共同界面不要求把两个页面合并成一个巨型StatefulWidget。

Mio当前的SdkSourceBinding默认可归为同名SDK分组；后续SDK通过登记加入。现有SourceSheet保留给手动改词、别名、验证、歧义作品选择和重试，不再作为每次常规切线都必须进入的检索页。

## 5. 统一行为约定

1. 进入详情页即显示SDK和线路骨架，来源发现、目录准备并行推进；有可用候选即可展示，慢站点不阻塞其他站点。
2. 只将明确同作品、版本无冲突的结果转换为线路候选；多条同名无法确认时显示“需确认作品”，不随机取第一条。无资源、目录失败、缺当前集、待检测分别显示。
3. 初始选集由已验证历史优先；无历史使用已有明确目录。直接详情入口与搜索预载入口都复用同一SDK/线路展示，自动播放仍服从入口配置和浏览器手势限制。
4. 自动只在当前SDK中尝试，保留真实当前集；AniFive的范围是其受管四站，不包括其他SDK与未知自定义规则。
5. 手动选择线路立即匹配当前集并解析，保持手动锁定；无该集保留原播放并提示，特殊集不能靠数字猜测。
6. 画质已知时按真实档位与首帧表现优先；未知时按已验证目录、当前集匹配、成功率、首帧耗时等策略排序，不伪造“最高”。获取目录/画质可并发，消耗token和安装媒体必须串行。
7. 新解析期间保留旧媒体；切换成功时更新活动身份。跨版本只在时长等兼容证据成立时交接时间偏移，否则从头并提示。
8. 线路弹层刷新本会话状态，避免每次打开都全量重搜。关闭弹层不等于取消整页已准备好的缓存；退页、换作品、换SDK则取消过期工作。
9. “共N条”只统计该作品实际返回的线路，待检测/失败/缺集保留各自状态，不把四个站点当成固定四条线路。
10. Web和Android共用同一面板与选择语义；平台差异只在传输、播放器和媒体请求头，不分叉出两套选源规则。

## 6. 最小实施切片

| 切片 | 主要位置 | 交付/检查 |
|---|---|---|
| 1 分组与线路身份 | SourceProfile/分组登记、四源配置、Road/可选线路映射 | SDK与provider分离，旧规则可序列化、无名称猜测 |
| 2 共用展示 | sdk_source_widgets或新公共source panel、两类详情页 | 顶层AniFive/miomedia，独立线路卡、分组弹层、选中与当前区分 |
| 3 会话与选择 | SourceCandidates、VideoPageController、SDK协调器及页面选择入口 | SDK内自动、手动锁定、当前集匹配、迟到取消、先准备后提交 |
| 4 回归与规范同步 | 相关测试、统一SDK规范、两端实际页面 | 历史/收藏/自定义规则/下载不退化，实播/取消和窄屏通过 |

预期涉及共享契约和播放会话，属于L级跨模块改动。若执行，先固定此分析中的行为约定，按四个切片交付；如采用OpenSpec再经一次确认创建工件，分析本身不自动创建OpenSpec文件。

## 7. 验收重点

- 动漫顶层只出现已登记AniFive SDK标签，四站在其线路弹层；新增SDK可再增加标签，不覆盖现有providerId。
- 影视继续显示miomedia等SDK标签，真实动态线路数量不变；未支持的动漫SDK不出现在可点标签中。
- AniFive聚合多站真实线路，C实际线路2仍按原引用播放；B不透明路径、A倒序/SP集不发生错集。
- 自动勾选与“当前使用MXdm/线路X”同时可见且不冲突；手动点线路后只锁定该线路；取消自动不丢目标集。
- 多来源错年/错季/同名歧义不自动归并；单站慢、失败、缺集不会阻塞其他可用站，也不会被标成完全无资源。
- 切换SDK不重置为首集；同集匹配失败保留原播放；新目标未首帧前不能标成正在播放。
- 无qualities时显示优选策略/画质待确认；有真实档位时才显示最高已知画质；媒体头replace和D的MP4端口策略沿用。
- 旧DM84/MXdm/akianime/moonci/aafun历史可恢复；收藏、Bangumi讨论/弹幕、下载关联和同名自定义规则保持正确身份。
- Web/Android验证搜索进入和直接资料进入、自动、手动、换集、换SDK、拖动、失败重试、快速连续选择、退页取消、仅一个活动播放器。
- 320px/2倍文字/长线路列表/读屏/减少动效仍可用。

现有参考测试：[SDK顶层来源/当前与自动标识](../../test/miomedia_sdk_ui_test.dart#L232)、[SDK身份隔离](../../test/sdk_playback_entry_test.dart)、[选线协调器](../../test/sdk_playback_coordinator_test.dart)、[动漫同集准备](../../test/content_search_playback_test.dart)、[真实URL历史恢复](../../test/anifive_history_identity_test.dart)。这些是可扩展的测试入口，不表示本轮已执行或新分组已实现。

## 8. 本轮结果

- DONE：两类详情页、来源会话与既有测试的代码梳理。
- DONE：确认按SDK分组的目标，并明确站点/线路/剧集身份、自动范围和状态设计。
- DONE：共用来源面板、AniFive四站真实线路、SDK内自动恢复、手动锁定和跨SDK同集切换已实施。
- DONE：根据用户截图收紧来源栏与线路弹层，固定自动选项，按站点展示紧凑线路按钮。

后续实施与验证记录见[分组和紧凑布局实施记录](../development/anime-playback-source-alignment-verification-20261015.zh.md)。Web的MXdm样例与雷电的moonci持续播放、换集和历史均已有运行证据；第三方线路失败和未覆盖范围仍分别记录，不把样例通过扩大为全站通过。
