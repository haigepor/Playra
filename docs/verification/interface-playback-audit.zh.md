# 接口、算法与 Web/Android 播放核验

日期：2026-10-12。范围：已接入接口、16 条动漫规则、抽样作品发现的所有线路代码；不是全平台作品或全剧集穷举。

## 结论与本次落实

接口仍有提速空间，主要在网络、重复读取、请求调度和大报文解密。不能通过更换播放器消除服务端换取或解析等待。

已修复 Web `Media` 非空请求头触发 `UnsupportedError` 的实际故障。来源头部仍编码给同源媒体网关；Android 保留原生头部。六个 SDK 模块保持原样，设备身份未替换，主路径核验累计 rotations 为 0。

进一步完善两端共用行为：

- 作品会话内按线路缓存剧集五分钟，合并相同在途读取，快速换线不重复清空底层结果。
- 显式选择的线路优先；起播失败后最多再尝试两条能够严格匹配同一集的线路。已验证可起播的线路优先，未知线路其次，近期失败的线路最后；同档按近期耗时排序。成绩按平台/线路保存在内存，冷启动不会保留。
- 特辑唯一完整名称匹配，普通集名规范化集数匹配。使用目标线路真实编号，拒绝同名歧义和数组位置猜测。返回选择与作品/线路/剧集不一致时终止。
- `stop/open` 串行，重新绑定当前尝试的媒体错误监听；取消选择和离开页面使迟到结果失效。
- 25 秒起播窗口结合视频尺寸和进度，媒体就绪但暂停时保留点击继续的路径。这个信号是运行状态判据，逐帧解码仍需独立验证。
- 当前集标记为固定 14 dp 三柱动画，暂停/缓冲停止，减少动画、后台和隐藏 ticker 时静止，仅局部重绘。

**实际 Web 页面恢复已通过：**《吞噬星空》默认 `dym3u8` 起播失败后自动选择 `ffm3u8`，视频为 1920×1080；后续观测 62.43 秒、累计 1876 帧。暂停后语义由“正在播放 第01集”变为“当前集 第01集”。

**Android 编译与运行必须分开：**独立原生验收包构建成功，但当前 Android 14 x64 模拟器安装报 `INSTALL_FAILED_MEDIA_UNAVAILABLE: Failed to restorecon`，随后找不到验收 Activity。包名已核对为 `com.predidit.kazumi.playbackaudit`，原应用未覆盖、未清数据。设备剩余空间约 22 GB，不能将错误归因为空间不足。此环境的实际 Android 解码仍 BLOCKED。

## 1. 接口边界

| 范围 | 数量 | 本次结论 |
|---|---:|---|
| 当前 SDK 文档提取的端点 | 132（130 POST、2 GET） | 清单事实，不等于 APP 全部支持 |
| Python 运行桥接公开操作 | 11 | recommend/banners/catalog/detail/episodes/qualities/exchange/search/searchConfig/hotRank/play |
| 实际经过 SDK 的不同平台路径 | 13 | 全部观测 HTTP 200 与业务码 200 |
| 内容样本池 | 52 个作品 | 6 类抽样，漫剧未找到样本 |
| 作品与线路组合 | 10 | 10/10 ready 与传输验证通过 |
| 抽样发现的不同线路代码 | 7 | 全部覆盖资源诊断，4/7 浏览器解码通过 |
| 内置动漫规则 | 16 | 全部执行搜索，继续检查有匹配的资源 |

没有批量执行账号、支付、奖励入账等写接口。已有 `docs/miomedia-endpoint-inventory.zh.md` 的接入数量早于搜索/榜单/播放编排扩展，应以当前 `OPERATIONS` 与本报告为准；本次未改写旧文档。

七天榜单继续使用 `/video/modules`、pageIndex=1、原模块标题与 items 顺序、分类隔离；不按累计播放量重排，不编造统计时间字段。

## 2. 实际耗时

计时客户端继承原 Client，网络耗时包括 `_post` 完整读取密文；本地差值包括签名、封装、解密及响应处理。表中为本轮小样本中位数，不能当作长期 SLA。

| 平台路径 | 次数 | 网络 ms | 本地 ms | 最大总耗时 ms |
|---|---:|---:|---:|---:|
| auth/negotiate | 1 | 279.92 | 10.55 | 290.46 |
| home/recommend | 2 | 374.89 | 22.66 | 411.70 |
| banner/list | 2 | 242.59 | 15.86 | 264.47 |
| video/searchConfig | 2 | 314.05 | 17.10 | 353.35 |
| video/categoryList | 8 | 551.52 | 14.76 | 1081.95 |
| video/modules | 2 | 1019.57 | 360.18 | 1756.39 |
| video/search | 6 | 418.99 | 19.64 | 533.62 |
| video/detail | 6 | 247.76 | 10.34 | 270.09 |
| resolve/episodes | 10 | 329.75 | 17.05 | 410.29 |
| ad/getConfig | 10 | 241.97 | 13.20 | 506.11 |
| ad/claimReward | 10 | 240.44 | 12.05 | 284.48 |
| resolve/qualities | 10 | 287.83 | 11.90 | 5257.07 |
| resolve/exchange | 10 | 252.38 | 16.87 | 641.04 |

常规播放包含 nonce→凭证与 qualities→exchange 等顺序请求，单请求约 240–330 ms 的网络耗时已经形成约一秒的基础等待。抽样播放换取总耗时约 1.08–12.59 秒，最长样本含一次 qualities 上游 5.26 秒等待及后续解析，不能归因于界面绘制。

30 次本地微基准中位数：读取身份 0.243 ms、构造动态签名头 9.259 ms、派生设备密钥 0.006 ms、小请求封装 0.476 ms。身份文件读取不是当前主要瓶颈；禁止缓存整套带时间戳/nonce 的签名头。

### 大报文算法热点

新采集的一份真实 modules 密文为 597290 字节、明文 447815 字节。带 cProfile 的解密总耗时 332.217 ms：

| 函数 | 累计 ms | 说明 |
|---|---:|---|
| m2_rc4s | 260.191 | 7 次，约占解密 78%，包含自身逐字节处理 |
| m4_tea_decrypt | 61.158 | 7 次，其中 _tea_lanes_dec 58.168 ms |
| m1_xor_decrypt | 7.344 | 占比较低 |
| M3 b64 解码 | 约 1.27 | 占比较低 |
| 协议解析 | 约 0.80 | 不是热点 |

这是另一份响应及算法链的实测，不能与此前速度报告逐字节直接比倍率。ECSM 容器已使用 bytearray 拼接，未发现需要修复的二次方 bytes 追加。M2 为自研变体，不能直接用普通 RC4 替换；SDK 算法本次未改。若 SDK 作者继续优化，应重点比较 M2/M4，并逐条验证既有向量和真实报文。

## 3. 线路传输与解码

传输检查验证 HLS 魔数、MIME、子列表、首片/密钥/初始化段，或 MP4 ftyp、Range 与非 HTML/JSON 内容。只读取验证所需的小段，不保存完整视频。

《吞噬星空》四条线路各 245 集；另有动漫电影、电影、剧集、综艺样本。10 个作品/线路组合全部 `ready`，传输检查 10/10。身份文件字节保持一致，attempts=10、adRequired=0、rotations=0。

以下是**修复后、增加自动恢复前**的资源解码隔离检查：同源媒体网关、MP4 或项目现有 HLS.js 1.4.10、静音、最长 25 秒，确认实际帧数与进度。HLS.js 强制分支是诊断路径，不等价于 Android 真机，也不等价于 media_kit 默认的浏览器原生 HLS 分支。

| 线路 | 样本 | 最终资源 | 浏览器解码 | 观测 |
|---|---|---|---|---|
| dym3u8 | 吞噬星空 | HLS | 未通过 | fragParsingError；0 帧 |
| ffm3u8 | 吞噬星空 | MP4 | PASS | 1920×1080，64 帧，2.02 秒 |
| lzm3u8 | 吞噬星空 | MP4 | PASS | 1920×1080，54 帧，2.07 秒 |
| gs3 | 吞噬星空 | HLS | 窗口内未确认 | 0 帧，25 秒；原生 HLS 另见 DEMUXER_ERROR_COULD_NOT_PARSE |
| TX | 海贼王 | MP4 | PASS | 1920×1080，55 帧，2.12 秒 |
| sb | 吞噬星空剧场版 决战原始星 | MP4 | 窗口内未确认 | 元数据未完成，25 秒 |
| dyttm3u8 | 电影电影 | HLS | PASS | 1080×551，56 帧，2.19 秒 |

gs3 的另一 HLS.js 诊断尝试出现音频解码/追加错误。超时不证明永久不可用；不以分片 MIME 单独认定根因，也不认为所有 HLS 都失败。上述失败源本身尚未修复，新增恢复改善的是用户起播路径。

## 4. 16 条动漫规则

关键词统一“吞噬星空”；搜索/剧集约 22 秒预算，每个有资源线路检查第一集。解析走现有 SourceGateway 和浏览器解析服务，未自动处理验证挑战。

| 规则 | 搜索 | 后续结果 |
|---|---|---|
| 7sefun | 4 个匹配，7.86 秒 | 244 集；1 条 MP4 传输通过，解析约 17.49 秒 |
| MXdm | 10 个匹配，2.30 秒 | 4 条线路，245/26/245/245 集；4 条 HLS 传输通过，解析约 3.83–13.46 秒 |
| DM84 | 2 个匹配，1.18 秒 | 245 集；解析服务约 30 秒后 DioException |
| baimao | 7 个匹配，8.56 秒 | 剧集读取 SOURCE_ERROR |
| AGE | SOURCE_ERROR | 搜索阶段失败 |
| aafun | SOURCE_ERROR | 搜索阶段失败 |
| dalvdm | SOURCE_ERROR | 搜索阶段失败 |
| giriGiriLove | CHALLENGE_REQUIRED | 需要验证，未执行挑战 |
| mgnacg | CHALLENGE_REQUIRED | 需要验证，未执行挑战 |
| mutefun | CHALLENGE_REQUIRED | 需要验证，未执行挑战 |
| akianime | NO_MATCH | 该关键词无结果 |
| ezdmw | NO_MATCH | 该关键词无结果 |
| moonci | NO_MATCH | 该关键词无结果 |
| sorani | NO_MATCH | 该关键词无结果 |
| xfdmneo | NO_MATCH | 该关键词无结果 |
| xfdmnext | NO_MATCH | 该关键词无结果 |

本轮为 2 条规则的 5 条线路传输通过，不是这 16 个站点全部可播放。NO_MATCH 不代表站点整体故障；SOURCE_ERROR 未含足够底层 HTTP 根因，不编造状态码。官方规则配置一致性与实时站点健康是不同验收项。

## 5. Bangumi 补充核验

经相同 Web 网关、按代码中的公开请求头/参数复测：搜索“吞噬星空”HTTP 200 返回 3 条；趋势 200 返回 10 条；作品详情、作品短评（5 条）、剧集（5 条）、剧集讨论均 200。分别约 1.76、3.08、1.15、7.07、2.61、1.03 秒。季节日历的先前读取为 200、78 KB、2.71 秒。

初步诊断中过一次搜索 502；趋势探针遗漏 type 参数得到 400。补正参数后均通过，因此不能把探针 400 当成项目缺陷；搜索 502 只能认作本次瞬态结果。MioMedia ID 不直接当作 Bangumi ID 使用，来源作品的评价/讨论不能因数字相似而跨平台查询。弹幕等凭证接口没有批量联网核验。

## 6. 可继续提速的位置

| 优先级 | 位置 | 依据与建议 |
|---|---|---|
| 已落实 | MioDetail 剧集读取 | 五分钟会话缓存与在途合并，保留取消/编号隔离 |
| 已落实 | MioDetail 起播恢复 | 首次选择优先，后续按实测成绩排序，最多 3 次，仅尝试存在匹配剧集的候选 |
| P1 | Python 公共内容调用 | 增加短 TTL/SWR 与请求合并；key 必须包括接口、分类、筛选、分页。无收益前不引入新依赖 |
| P1 | Runtime 4 个工作槽 | 当前满载立即 BUSY/429；内容请求与解析争用。可设计短队列和播放优先级，先做压测再调整 |
| P1 | 首页分类预取 | 已有分批通知，不是等所有结果才渲染；发现阶段仍会读取目录与筛选再启动已知分类请求。优先当前页，减少离屏批量加载 |
| P2 | 榜单大报文 | 最终 Top10 投影约 13 KB，但需先读取/解密约 600 KB 密文。短期缓存收益大于在客户端截断未知加密块 |
| P2 | Node/Python 连接 | Node gateway agent:false、Python urlopen 单次连接；核验按可信 origin/IP 池化的连接复用，不直接取消安全地址校验 |
| P2 | SDK 高层并行 | 凭证与 qualities 的独立分支可由 SDK 作者验证是否允许并行；nonce→凭证→exchange 等依赖不能打乱 |
| P3 | M2/M4 算法 | 交 SDK 作者优化与向量复验；签名/设备派生并非主耗时 |

禁止复用一次性 nonce、adToken、exchangeToken，禁止把短时效媒体地址当成长期缓存，也不缓存带时间戳的整套签名。不要盲目增加线程：纯 Python CPU 热点不能靠同进程线程线性加速。

## 7. Aliplayer 评估

阿里云官方 Web 播放器支持 URL 播放与 HLS/MP4。官方快速接入和 License FAQ 涉及不同 SDK 版本，正式选型需锁定版本、域名授权和 License；H.265/H.266 等能力另有条件。它仍受浏览器跨域、资源编码和来源头部约束，不能保证上述三种未通过样本自动修复。

本次保留已有 media_kit 和同源网关，无商业依赖变更。后续如果明确采用 Aliplayer，应增加 Web 专用适配器，以同一会话接口提供加载、播放、暂停、seek、错误和 dispose，原生 Android 保留播放器；按实际样本比较首帧、失败恢复和资源释放，避免一个页面同时启动两套播放器。

官方参考：[快速接入](https://help.aliyun.com/zh/vod/developer-reference/integration)、[Aliplayer API](https://help.aliyun.com/zh/vod/developer-reference/api-operations)、[Web License FAQ](https://help.aliyun.com/en/vod/developer-reference/faq-about-apsaravideo-player-for-web-1)。Context7 发现官方 Aliyun Player Web 仓库，但本轮查询未提供对应示例，判断以官方帮助页与当前代码为准。

## 8. 验证、产物与回滚

原始安全证据：`.dart_tool/interface-playback-audit-20261012/`。其中 `miomedia-live.json`、`anime-live.json`、`browser-decode.json`、`algorithm-profile.json`、`bangumi-live-corrected.json` 分别对应数据源、规则、解码、算法热点和补正后的 Bangumi 探针；不含密钥、凭证或完整媒体地址。

| 文件 | 用途与影响 | 回滚 |
|---|---|---|
| lib/presentation/modern/miomedia/miomedia_detail_page.dart | 修复 Web 头部、接入恢复与真实播放标记；影响 MioDetailPage | 同证据目录 miomedia_detail_page.before.dart |
| lib/services/source/miomedia/miomedia_playback_coordinator.dart | 会话缓存、匹配与有限恢复；不修改协议 | 新增文件，与页面接入一起移除 |
| lib/presentation/modern/miomedia/miomedia_playing_mark.dart | 固定尺寸、暂停/减少动画状态标记 | 新增文件 |
| test/miomedia_playback_coordinator_test.dart、test/miomedia_playing_mark_test.dart | 边界与动画验证 | 新增文件 |
| tool/source_runtime/miomedia_full_audit.py、tool/anime_live_audit.dart | 可重复执行的安全计时与传输诊断 | 新增脚本，无生产调用 |
| openspec/changes/stabilize-miomedia-web-android-playback/ | 本次约束和验收记录 | 新增独立 change，未归档 |
| 本报告与证据目录 | 结果、备份与独立 Android 验收包/入口 | 新增产物 |

重现诊断：

```powershell
python -u -X utf8 tool/source_runtime/miomedia_full_audit.py --play
& ./.tooling/flutter/bin/cache/dart-sdk/bin/dart.exe tool/anime_live_audit.dart
```

`dart run` 本轮触发了本地 Windows 原生构建钩子的 vswhere 输出 JSON 编码错误；直接 Dart 文件入口不需要这些钩子，完成 16 条规则诊断。没有为了诊断修改工具链或业务规则。

验证清单：

- DONE：SDK 自检 ALL PASS，playback 12/12；Python runtime 30 项测试通过（算法与运行桥接未修改）。
- DONE：缓存、取消、匹配、有限恢复、身份拒绝与减少动画测试，以及既有榜单/页面回归。
- DONE：Web 构建、真实 MioDetailPage 自动恢复、解码帧与暂停标记。
- DONE：独立 Android 验收包编译；原应用未被覆盖，新增 reverse 映射已清理。
- BLOCKED：该模拟器无法安装独立 APK，Android 实际解码；保留精确安装错误。
- NEXT：短 TTL 公共内容缓存、播放优先级调度、Aliplayer 授权配置后对照验证；均未伪报本次已实现。

恢复变更回归 27 项通过；最终 Web 构建 113.5 秒、常规 Android x64 debug 构建 36.9 秒。新版实际页面自动换线后观测 1080p、1124 帧；重新打开优先选已成功线路。高速→蓝光→高速→蓝光只新增一次剧集读取，缓存通过。UTF-8、SDK 六文件字节一致性与范围检查通过。后续独立 Android Python 包见 `android-embedded-python.zh.md`，其关联 Flutter 回归共 41 项通过。不能将以上抽样扩大成全站、全剧集或真实手机播放承诺。
