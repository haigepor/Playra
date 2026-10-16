# Lumina 4K 与线路切换核验

日期：2026-10-16。范围：本地 SDK、宿主公开协议、Flutter Web/Android 的来源与画质选择；不修改供应商算法或凭证参数。

## 结论

Lumina 是独立动漫主来源；AniFive 保留动漫规则，MioMedia 的动漫归入动漫分类、以低优先级提供备用，电影/剧集仍由 MioMedia 服务。内容身份不按片名硬转换，旧历史不迁移、不改 ID。iOS/ARM32 不启用 Lumina 的既定边界保持。

**线路与画质不是一回事**。`detail.parts[].play`（例如 `mp4`）是上游真实线路标识；`part` 是第几集的原文；同一线路解析后可返回多个不同画质的 CDN 地址。页面上的“线路3”来自上游名称，不能据此判断是 4K。

## 实际接口

| 层级 | 请求/返回 | 接入要求 |
|---|---|---|
| 目录 | detail.parts：play、线路名、原始 part 列表 | 保留同一作品、同一集的真实标识 |
| 凭证 | POST /app/video/play，id/play/part | **没有 quality/4k 参数**；不可自行添加 |
| 解析器 | data.playAddr[]：desc/title/vcodec/format/domain/addr | SDK 组装 name、url、headers；宿主转为 medias |
| 画质选择 | medias 中真实声明的 4K 或 1080P | 应用选对应直链；切换不改上游线路代码 |
| 媒体 | url + 原始 headers，支持 Range | 空 UA 与 Referer 也要原样保留 |

供应商文档 `docs/api/play.md` 记录：新结构测试样本有 1080P/4K 双档，H265/MP4，moov 可在文件尾部。此记录不代表每部作品、每集、每条线路都具备双档。

本轮实际通过当前 Web BFF 请求《沧元图》111075、《海贼王》1239 的 mp4 / 第1集，均 status=ready，但只返回 name=mp4 的单直链、vcodec=null。这是无画质元数据的旧结构，不能标记 4K 或假定为 1080p。原 SDK 与导入副本的 play/client/auth/block/envelope 摘要一致。

进一步按集抽查：《沧元图》第99集确实同时返回1080P高清/4K超清，均H265/MP4；《大主宰年番》第95集仍为未知画质单链。对前者两档只读取Range头部和moov元数据，均HTTP206、video/mp4，视频轨实际宽高分别为1920×888、3840×1776；宽银幕裁边不能强行改写成1920×1080/3840×2160。档位必须逐集判断。

## 当前修复

原封装 `supportsQualities=false`、忽略 quality，最终直接使用 media[0]，因此“自动最高画质”并不能帮助 Lumina 选择双档结果里的 4K。

现在 Lumina 从同一次解析的 medias 识别明确的 4K/1080P 声明，顺序为 **4K → 1080p → 其他已知档位 → 未知画质**。首次画质探测与准备复用同一次网络结果；档位描述与短效直链分开，直链最多27秒内消费一次，过期或403刷新会重新取凭证。SDK 不接收新的 quality 参数，选择全部在接入层进行。

自动选择在当前 SDK 的同集候选内比较；手动锁定线路后，4K 失败只可退该线路的1080p，不跳到别的线路/SDK。缺少请求档位时返回 QUALITY_UNAVAILABLE，不能把1080p地址回报成4K。旧结构仍可播放，显示画质待确认；实际出画后使用解码宽高作为事实，来源声明与实际分辨率分开。

显示名仅在展示层映射为“动漫 · Lumina”“动漫 · AniFive”；Mio 的真实动漫内容为“动漫备用 · MioMedia”，其他影视为“影视 · MioMedia”。内部 providerId、作品/剧集引用、历史收藏字段保持原值。

## 切换与验证边界

本轮后续已新增独立手动画质控件，真实双档显示自动/4K/1080p；线路锁与画质锁分别保存。明确选档只尝试该档位，缺档提示选择其他档或自动；恢复自动画质不解除手动线路。绑定provider/contentId/play/part/quality，同集切换在提交前读取最新进度，按目标时长校验恢复并保持暂停；不通过改集数或改线路名实现。多SDK交互与剩余能力见[交互核验](sdk-interaction-audit-20261016.zh.md)。

4K 直链不等于必定能播：短效地址可能403，H265依赖端侧解码，尾部moov要求Range正确；Web必须以实际出画/解码帧推进验证，HTTP200不能代替。未知档位不得当作4K失败后的1080p成功。

回归覆盖：乱序双档选4K、无4K选1080p、手动同线4K失败降1080p、旧单链未知画质、失效重取、缺档不冒充、取消不返回旧链；全量Flutter730项通过。Web真实UI从《沧元图》目录选第99集，自动准备2160p来源声明，点击前没有video；显式点击后实际解码3840×1776，时间10.610598→20.147621秒，解码帧265→504，无媒体错误，随后暂停。页面已显示实际宽高而非继续把来源声明当实测。Android结果另见统一验收报告。

实现入口：`lumina_playback_provider.dart`、`sdk_playback_coordinator.dart`、`sdk_playback_entry.dart`、`content_providers.dart`、`source_display_names.dart`、`sdk_player_detail_page.dart`；回退应先保存本轮未提交补丁，按文件恢复这些接入层改动，保留全部存储和供应商SDK。
