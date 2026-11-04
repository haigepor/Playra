# 首页双内容源整合分析（2026-11-03）

> 目标 App：`C:\Users\haige\Desktop\Playra`（Flutter，包名仍是 `kazumi`，品牌 Playra），基线 `763f1ae2`。
> 本文回答一件事：**把两个内容源接进同一个首页，动漫优先用已经接好的那个**——需求怎么拆、数据怎么来、页面怎么排、边界在哪、下一步做什么。
> 证据标记：`[OBS]` 实测/代码可见，`[HYP]` 假设但未验证，`[VER]` 已用运行结果验证。

---

## 0. 一句话结论

首页分类行 = **推荐 / 热门 + 7 个风格频道**；**动漫主线仍是 Lumina**（首屏大图、片单、榜单全部沿用），第二个内容源（代号 **Whisklet**，即追剧喵协议）承接**其余 6 个风格页**（电影 / 电视剧 / 综艺 / 短剧 / AI漫剧 / 电视直播），并在推荐、热门、动漫三处作为**补充货架**出现。两个源互不阻塞：第二源全挂时 Lumina 页面照常出片，反之亦然。

---

## 1. 需求拆解（原话 → 工程项）

| 用户原话 | 工程项 | 落地位置 |
|---|---|---|
| 顶部的 tab 保留 热门和推荐 这两个 | 两个聚合位保持原位，排在风格频道之前 | `HomeFeed.recommended/popular` + `_FeedTabsState.feeds` |
| 整理当前 2 个数据源展示数据 | 新增第二个源的编解码 / 客户端 / 目录 / 控制器四层 | `lib/services/source/whisklet/` |
| 动漫的优先使用当前已经接好的 | 动漫页主源不变（Lumina 首屏 + 片单 + 榜单），第二源只加一条副货架 | `ModernHomeView` 动漫分支 + `whisklet-anime` 栏 |
| 更新其他 tab 页面 渲染这些数据 | 6 个风格页由第二源独立出片（分页网格 + 续页 + 重试） | `_WhiskletStyleGrid` + `HomeStyle` |
| 分析我的需求 整合整理好 | 本文 + 交接文档状态更新 | `docs/analysis/`、`docs/handoff-home-header-redesign.zh.md` |

### 1.1 「2 个数据源」的判定依据

- `[OBS]` 整合前 `lib/services/source/` 下只有 `lumina/` 一个实现；`SdkRankController(lumina:)` 只有 Lumina 注入口；`docs/` 与 README 写明「仅接入 Lumina」。
- `[OBS]` 用户截图里的分类表（`1 电影 / 2 电视剧 / 4 动漫 / 5 综艺 / 21 短剧 / 22 Ai漫剧 / 20 电视直播`）在 Playra 代码里**没有对应概念**（Playra 用 `ContentGroup` + Lumina 频道 id，不是 tid）。
- `[VER]` 该 tid 表与第二个源的 `video_list` 参数逐项一致，七个 tid 全部实测出片（见 §2）。⇒ 第二个源 = 追剧喵协议（本仓库内部代号 **Whisklet**）。

---

## 2. 第二源接口面（真连实测，2026-11-03）

### 2.1 信封

| 方向 | 形态 |
|---|---|
| 请求 | `base64url( IV(16) ‖ AES-128-CBC-PKCS7(json) )`，key = `md5(buildTime + 盐 + 包名)`，`text/plain` + 版本/PK 头 |
| 响应 | 三段式 base64 信封；尾部 `xddappsecretkey<len>` 仅 `app_config` / `video_detail` / `secret_parse_api_url` 带 |
| 详情特例 | `video_detail` 明文头部被上游截断，取 `"vod_info":` 起始并按 `{"code":1,"data":{` 补头复原 |

### 2.2 七个风格频道 `[OBS]`（`video_list`，pg=1；上游忽略 `limit`，固定返回 21 条/页）

| tid | 频道 | pagecount（总页数） | 第 1 页首条 |
|---|---|---|---|
| 1 | 电影 | 3324 | 生化危机：爆发夜 |
| 2 | 电视剧 | 2059 | 尚公主 |
| 4 | 动漫 | 3997 | 胡桃夹子2026 |
| 5 | 综艺 | 696 | 舞蹈新风暴 |
| 21 | 短剧 | 352 | 醒来成了炮灰嫡女：九王的命我保定了2 |
| 22 | AI漫剧 | 504 | 万古神帝AI漫剧 |
| 20 | 电视直播 | 1 | 卫视频道（该页仅 2 条，上游就这么多） |

`pagecount` 语义验证 `[VER]`（tid=1）：`pg=2` 首条不同；`pg=3324` 返回 13 条（末页）；`pg=3325` 返回 0 条 ⇒ **pagecount 是总页数，不是总条数**。短剧页数在两次实测间 351→352，属上游实时变动。

### 2.3 推荐与热门

- `[OBS]` `index_recommend` → `data.videos` 共 **3 栏 × 6 条**：`热剧推荐` / `热门综艺` / `热门动漫`，另有 `data.banners`。
- `[OBS]` `rank_list` 只返回 **5 个榜名**（剧集热榜/电影热榜/动漫热榜/综艺热榜/短剧热榜），**没有任何条目接口**。
  ⇒ 「热门」必须由分类首屏合成：取 5 个榜单分类（`tid = 2,1,4,5,21`）第 1 页，按分类轮转交错、按作品 id 去重。`[VER]` 实测合成结果 >20 条、首 5 条跨多个分类。
  ⇒ 文案规则：**禁止写成「七天榜 / 近七天」**——上游没有统计窗口字段。

### 2.4 详情与线路

- `[OBS]` `video_detail` → `data.vod_info.vod_url_with_player[]`，每条线路含 `code` / `name` / `parse_api` / `url`；`url` 是 `#` 分隔的 `名称$token` 选集表。
- `[VER]` `WhiskletCatalog.lines()` 真连解析出线路 + 选集（含 token），live 用例断言通过。
- `[HYP]` `parse_api` 非空的线路要经 `secret_parse_api_url` 换直链（该步属于播放链路，本轮未接，见 §5）。

### 2.5 平台放行

- `[OBS]` `android/app/src/main/AndroidManifest.xml:5` `usesCleartextTraffic="true"`；`ios/Runner/Info.plist:46` 与 `macos/Runner/Info.plist:40` 均有 `NSAllowsArbitraryLoads` ⇒ 该源的明文 HTTP 在 Android / iOS / macOS 三端都不被系统拦。

---

## 3. 整合结构（已落地）

### 3.1 新增文件

| 文件 | 职责 |
|---|---|
| `lib/services/source/whisklet/whisklet_codec.dart` | 请求加密 / 请求回显解密 / 响应信封解码（含详情截断补头） |
| `lib/services/source/whisklet/whisklet_client.dart` | 8 个方法封装 + 按方法的载荷校验 + 失败映射 `SourceException` |
| `lib/services/source/whisklet/whisklet_models.dart` | `WhiskletWork / Shelf / Page / Line / Episode`；HTML 实体清洗 |
| `lib/services/source/whisklet/whisklet_catalog.dart` | 分类分页、推荐分栏、热门交错合成、详情线路解析 |
| `lib/services/source/whisklet/whisklet_home_controller.dart` | `HomeStyle`（tid ↔ 中文标签 ↔ `ContentGroup`）+ 每风格独立的分页/加载/失败状态 |
| `test/whisklet_live_test.dart` | 6 条真连验收，`--dart-define=WHISKLET_LIVE=true` 才跑 |

依赖：`pubspec.yaml` 新增 `pointycastle: ^3.9.1`（AES-128-CBC + PKCS7，纯 Dart，不引平台插件）。

### 3.2 分类行与数据源路由

| Tab（顺序） | 主内容 | 第二源货架 |
|---|---|---|
| 推荐 | Lumina 首屏（bento）+ Lumina 频道货架 | 3 栏推荐（热剧推荐 / 热门综艺 / 热门动漫） |
| 热门 | Lumina 首屏 + Lumina 频道货架 | `热播 · 第二源`（5 分类交错合成） |
| 电影 | — | 第二源网格（tid=1） |
| 电视剧 | — | 第二源网格（tid=2） |
| **动漫** | **Lumina 首屏 + 片单 + 榜单（优先源不变）** | `动漫 · 第二源`（tid=4，补充货架） |
| 综艺 | — | 第二源网格（tid=5） |
| 短剧 | — | 第二源网格（tid=21） |
| AI漫剧 | — | 第二源网格（tid=22） |
| 电视直播 | — | 第二源网格（tid=20） |

- `HomeFeed.screen` / `HomeFeed.comicDrama` 仍保留在枚举里供搜索等入口使用，但**不再进分类行**（没有对应内容源）。
- 动漫子分类（新番/日漫/国漫/动漫电影）本轮随分类行一起退出首页；对应枚举保留，供后续接回或搜索使用。
- **分类纯净性收口（2026-11-03）**：除推荐/热门/动漫外，六个第二源风格频道只渲染本分类网格。`HomeFeed.hasContentSource` 排除 `isWhiskletStyle`；首页五处渲染条件收敛（Lumina 横幅/加载骨架/继续观看/榜单/兜底精选），`_syncRanking` 对风格频道直接返回、不预取榜单。回归用例：`style channels keep only their own second-source content`。
- **播放源样式（2026-11-03）**：两个播放页共用 `PlaybackSourcePanel` 左右单行——左侧「播放源」标签、右侧当前源名（源名独占剩余宽度右对齐，仅在真正放不下时省略），**线路名/分辨率/画质/来源声明全部移入点击后的播放源弹窗**；弹窗内同屏提供播放源切换、自动选线、线路与画质。行高 48、`StadiumBorder` 胶囊；选集按钮、分段条、个人库卡片、继续观看卡片同步胶囊化，全局 `ChipThemeData` 与按钮主题统一 `StadiumBorder`。

### 3.3 状态与失败处理

- 每个 `HomeStyle` 独立持有 `_items / _page / _pages / _loading / _failed`：一个频道失败不影响其它频道，也不影响 Lumina。
- 网格页首屏失败 → 就地面板 + `重试`（`ValueKey('whisklet-retry-<style>')`）；续页失败 → `hasMore` 置假，不再空转请求。
- 推荐 / 热门 / 动漫副货架的失败各自独立：`hotError` / `shelfError` / `failed(anime)`，都能就地重试。
- 第二源整体不可用（DNS、超时、信封变更）时：Lumina 的推荐/热门/动漫正常出片，风格页显示失败面板——不会出现「全站空白」。

### 3.4 与 Lumina 的边界（为什么不合并成一层）

- Lumina 是 `LuminaHomeController + LuminaPlaybackProvider`（已有播放链路、榜单、频道 bucket）；
- Whisklet 的条目 id / 线路 / token 形态与 Lumina 完全不同，合并会把「播放器怎么取流」的分叉塞进首页控制器；
- 因此首页只做**并列展示**：两个控制器分别 `notifyListeners`，`HomeFrameUpdates` 同时订阅，互不引用内部状态。

---

## 4. 验收记录（本轮实跑）

| 项 | 结果 |
|---|---|
| `flutter pub get` | 1 个依赖变化（pointycastle） |
| `flutter analyze --no-pub` | 全仓 482 条 `info`（预存）；**本次触碰文件 0 条** |
| `flutter test test/whisklet_live_test.dart --dart-define=WHISKLET_LIVE=true` | **6/6 PASS**（七频道出片、热门交错去重、推荐分栏、详情选集、控制器续页、卡片字段） |
| `flutter test test/modern_home_view_test.dart test/interface_navigation_test.dart` | **20/20 PASS** |
| 本次触碰的 8 个用例文件 | **49/49 PASS**（播放源面板、空线路、画质、来源切换、首页纯净性、导航） |
| 二次复核 11 个用例文件（含个人库来源名） | **51/51 PASS**（新增 `second source never leaks its wire id into library records`） |
| `flutter analyze --no-pub`（二次） | 481 条 `info`（预存）、0 error / 0 warning |
| `flutter test`（全量） | **719 通过 / 1 跳过 / 3 失败**（二次复核后） |
| 3 个失败用例 | `browse_auto_load_test`、`content_skeleton_test`、`modern_profile_test` |
| 3 个失败是否本次引入 | **否**：在 `763f1ae2` 的独立 worktree（补入被 gitignore 的 native 资产）复跑，同样 3 条失败 |

未执行（`NOT RUN`）：
- ~~真机 / 模拟器 E2E~~（**已于同日真机完成，见 §4.1**）；
- ~~第二源的播放链路~~（**已于同日交付并真机验收，见 §5**）；
- 视觉验收截图（头部与九宫格样式未出图）。

### 4.1 真机 E2E（LLD-AL20，Android 9，arm64，2026-11-03）

`[VER]` 全部实测通过，共 10 组截图（`/c/tmp/playra-e2e/`）：

| 项 | 结果 |
|---|---|
| 构建/安装 | `flutter build apk --debug --target-platform android-arm64`（28–99s）；装机版 2.4.2 签名 = 本机 `~/.android/debug.keystore`（SHA256 逐字节一致）⇒ `adb install -r` 保留数据 |
| 首页推荐 | Lumina 首屏 + 第二源 3 栏推荐出片（嫁金钗/尚公主=上游实测同名条目） |
| 热门 | Lumina 排行+频道货架 + `热播 · 第二源` |
| 动漫 | Lumina 主源（热播推荐 1/2/3，豆瓣海报）+「动漫 · 第二源」货架（彭彭丁满/转生成哥布林…，tid=4 真实片单） |
| 短剧网格 | tid=21 真实条目 + `已完结/更新至第18集` 角标；封面并发加载后 9/9 出片 |
| 卡片点击 | SnackBar「《追风少女》来自第二内容源，播放链路将在下一阶段接入」（Stage B 边界符合设计） |
| logcat 终检 | FATAL/Unhandled/EXCEPTION=0；图片失败全程仅 1 条（`pic.ry-pic.com` 首连被断，重试后成功）；Lumina 引擎日志正常 |

**真机抓出并已修复的两个缺陷**：

1. **动漫副货架永远空**（真机发现）：`_syncWhisklet()` 的分支漏了 `HomeFeed.anime`——动漫被刻意排除在 `isWhiskletStyle` 外后，切到动漫 tab 时三个分支都不命中，`loadStyle(HomeStyle.anime)` 从未被触发。已补分支 + 新增联动回归用例（`test/modern_home_view_test.dart`，21/21 过）。
2. **豆瓣海报 403/418**（logcat 定案）：`NetworkImgLayer` 用裸 `CachedNetworkImageProvider`，豆瓣系图床对无 UA/Referer 请求回 418/403（宿主机复测：不带 418，带 UA+`Referer: https://www.douban.com/` 200）。修复：新增 `httpHeadersForImageUrl()`（`lib/utils/image_extension.dart`）按域注入——只对 `*.doubanio.com / *.douban.com` 加 UA+Referer，其余域名刻意不加头（腾讯系 CDN 历史上对带 Referer 的请求回 404）；Web 分支 `CachedBytesImageProvider` 同步支持 headers 并纳入缓存键相等性。修复后真机豆瓣零失败。

**图片"加载不出来"的完整归因**（三类，只有一类可修）：

| 类别 | 证据 | 处置 |
|---|---|---|
| 慢（并发 21 张 × 高 RTT 图床） | 同一屏等 10s 后 8/9 补齐、9/9 最终出片 | 无需修；属正常首屏时序 |
| 死图床（上游数据质量） | `snzypic.com`：宿主机 TLS 连不上，ICMP 应答 IP 反查已易主；`pic.ry-pic.com`：宿主机 403（150B 页面） | 客户端只能占位/等重试，改不了上游 |
| 豆瓣防盗链 | 418/403 → 修复后 0 失败 | **已修**（按域注入请求头） |

### 4.2 播放源样式真机复核（2026-11-03 二次）

`[VER]` 构建 `flutter build apk --debug --target-platform android-arm64`（50.1s）→ `adb install -r` Success 后逐页截图核对：

| 页面 | 实测结果 |
|---|---|
| 动漫详情（Lumina） | `播放源 动漫 · Lumina` 完整显示；行高 48、胶囊、右上收藏入口 |
| 动漫播放源弹窗 | 同屏：`自动（优选线路）` 选中态、`线路3 · 2160p · 来源声明`、`画质 自动 / 4K / 1080p`（胶囊 chip） |
| 选集区 | 5 个选集按钮全部胶囊（选中态描边 + 均衡器图标） |
| Whisklet 详情（综艺） | `播放源 Whisklet`、15 集胶囊选集；弹窗 9 条线路（独家②/测试kf/官方①/备用①-⑥） |

**本轮真机抓出并修复的两个缺陷**：

1. **源名被截断成「动漫 · Lum…」**：`PlaybackSourcePanel` 内 `Spacer()` 与 `Flexible` 同时 flex 1，剩余宽度被平分。改为 `SizedBox(width: 12)` + `Expanded(Text(textAlign: TextAlign.right))`，源名独占剩余宽度。
2. **追番记录打不开 + 露出接口 id**（截图发现卡片显示 `whisklet · 在看`，点开弹「当前平台暂不支持此来源」）：
   - `SdkLibraryRecord.sourceName` 自带一份 switch，新来源落到 `_ => providerId`；改为委托 `playbackSourceName()`，并给 `whisklet` 补显示名，个人库与播放源行自此共用一张名称表。
   - `openSdkLibraryRecord()` 的来源白名单只有 `lumina`（与 §5.2 修过的 `info_module` 白名单同源缺陷）；补 `whisklet` 分支，用进程内共享的 `WhiskletPlaybackProvider` 打开，避免每次进页新建连接池。

修复后回归：11 个用例文件 **51/51 PASS**（新增 `second source never leaks its wire id into library records`）；`flutter analyze` 481 条 info、0 error/warning；真机追番卡片显示 `Whisklet · 在看`，点开进详情页（无 toast），播放源弹窗正常。

---

## 5. 播放链路（Stage B，已交付并真机验收）

### 5.1 交付形态

`WhiskletPlaybackProvider extends SdkPlaybackProvider`（`lib/services/source/whisklet/whisklet_playback_provider.dart`），三路解析按线路 `parse_api` 分派：

| 线路形态 | 解析方式 | 判据 |
|---|---|---|
| `parse_api` 为空 | **直链**：令牌本身就是可播地址（lzcdn 裸 GET 200 `#EXTM3U`，无请求头） | live 8/8 中实测 200+`#EXTM3U` |
| 含 `/ajiami/` | **家族**：`secret_parse_api_url(url, player_code=线路自身代号)` 反复重发直到 `data` 达满长（信封丢头非加密；co=88/BBA=800/NBY=288/zijianm3u8=172/rose=232/youku=144/qq=144），再 GET `parse_api?url=<param>` 取 `{code:200,url}`；25 轮 × 350ms，player_code 用线路自身代号首轮即满长（A/B 实测 co 1 轮 vs BBA 3 轮） | param 满长为协议通过判据 |
| 其余 | **外部解析器**：令牌直接拼模板后，多数已自失效 | 失败报 `PARSER` |

- 上游解析后端（coffee-api.1ljx.com）有自己的**日点数配额**：`403 +「已达到今日最大请求点数限制(500000点)」`是配额打满而非协议错误 → 映射为 `{'status':'unavailable','error':'UPSTREAM_LIMIT'}`，UI 提示换线路，不伪装成功。
- `WhiskletClient` 的 `secretParse` 载荷校验放宽为 `value is String`（截断形态是丢头现象，由上层按满长重试，不视为协议错误）。
- `WhiskletCatalog` 新增 `info(id)`（`vod_info` 缓存 ≤24 条，详情/线路/播放共用一次网络往返）与同步 `linesFrom()`。

### 5.2 路由接线

- 首页第二源卡片 → `ModernHomeView.onWhiskletDetails` → `discover_page` push `/info/` + `SdkPlaybackEntry(title, cover, sources: [SdkSourceBinding(provider: whiskletPlayback, contentId)])`；provider 与目录共享同一 `WhiskletClient`，随页面 dispose。
- `info_module.dart` 的守卫从 `provider.id == 'lumina'` 白名单放宽为 `entry is SdkPlaybackEntry` 类型检查：旧 bangumi 入口（arguments 非 SdkPlaybackEntry）仍被挡进「旧来源作品详情」占位，而仓库内全部 `SdkPlaybackProvider`（Lumina / Whisklet）统一进 `SdkDetailPage`。真机首轮验证抓到：Whisklet 条目曾被白名单误挡到占位页，放宽后解决。

### 5.3 真机验收（2026-11-03，LLD-AL20）`[VER]`

| 步骤 | 结果 |
|---|---|
| 电影 tab → 点第二源卡片 | 进详情页（不再弹 SnackBar）：标题/年份/地区/简介、`播放设置 Whisklet`、12 条线路、46 集选集 |
| 点播放 | 播放器拉起 → 缓冲 → **出画**（片头发行许可证帧清晰可见）；logcat `ACodec OMX.IMG.MSVDX.Decoder.AVC` 硬解启动 |
| 播放状态 | `上次看到 1 · 0:02` 进度落库；线路自动选择后探测到 **1440×810 实际分辨率** |

宿主机真连回归：`flutter test test/whisklet_live_test.dart --dart-define=WHISKLET_LIVE=true` → **8/8 PASS**（新增直链 `playEpisode`→GET 200 `#EXTM3U`、家族线 ready/`UPSTREAM_LIMIT` 双形态断言两条）+ `test/modern_home_view_test.dart` **22/22**（新增卡片点击回调用例：回调接管后不再弹占位 SnackBar）。

### 5.4 剩余边界

- 家族线在上游配额打满时会话内返回 `UPSTREAM_LIMIT`（换线路可播）；直链线不受配额影响。
- 外部解析器线路多数已自失效，失败报 `PARSER` 并提示换线。
- 电视直播上游只有 2 条频道，属数据侧事实。
- 第二源是第三方明文 HTTP 接口，域名/端口/入口已做成 `--dart-define`（`WHISKLET_HOST/PORT/ENTRY`）便于轮换。
- `WhiskletClient.ranks()` 已实现但未使用（上游只给榜名），保留待上游补条目接口。

---

## 6. 参考

- 交接文档：`docs/handoff-home-header-redesign.zh.md`（头部规格；本次在文首补了状态说明）
- 头部设计：`docs/analysis/home-header-redesign-20261103.zh.md`
- 平台矩阵：`docs/analysis/lumina-platform-matrix-20261103.zh.md`
- 第二源协议取证（仓库外）：`instruct/tv-reverse/workspace/com.jjpengcheng.callshow.zjmc/probe_live_20261103.py`
