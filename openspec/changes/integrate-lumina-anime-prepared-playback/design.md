## Context

基准为 `49970c02`，初始工作区干净。现有可执行运行适配器为 MioMedia + AniFive A/B/C/D；内置动漫规则实际为4条，Bangumi为独立资料源。SDK页已有共享播放协调器，但 autoPlay=false 当前意味着完全不解析；动漫旧链进入详情会立即打开播放器。

用户已确认使用 OpenSpec 并实施，且补充：host为出厂占位，必须显式注入；DEVICE_FP生成一次持久复用；resolve=False仍有网络。零依赖下只有随包 `_fuse` 支持的平台可本地执行；ARM32保留旧来源。iOS最初评估受控远端服务，最新范围已改为隐藏Lumina、保留旧动漫来源。

## Goals / Non-Goals

**Goals:**
- Lumina频道/浏览/搜索/详情及完整直链解析优先，不伪造Bangumi身份。
- 详情自动准备但等待点击播放；取消旧结果，短效缓存不持久化。
- 请求头原样传递，特别保留空User-Agent及来源Referer。
- 三端共享业务契约，在可运行的平台上给出真实证据。

**Non-Goals:**
- 不重写供应商算法，不增加Unicorn等Python第三方依赖，不启用设备桥。
- 不改写ARM32算法降级；不在iOS启动本地Python或捏造iOS构建通过。
- 不重置旧历史、收藏、自定义规则，不将Lumina ID塞入旧Bangumi库。
- 不为本次接入新增独立SDK收藏体系；不接账号/广告/消息等非内容接口。

## Decisions

### 独立SDK内容身份

采用 `ContentSearchProvider + SdkPlaybackProvider + SdkDetailPage`，通过显式priority选主数据，不能依赖并发完成顺序。Lumina仅参与动漫领域；旧动漫规则和资料仍可用，Mio影视不改变。原始视频ID保持字符串，parts的play和part原值进入播放请求；SDK分集增加opaque reference，数字集号仅在来源标签有证据时存在。

### 自动解析与播放意图分离

采用 `idle → resolving → prepared → opening → playing`。准备只调用SDK/规则解析，不调用媒体open/init，不写正在播放/历史或首帧健康成功。PreparedPlayback按SDK、作品、线路、真实分集、画质及generation绑定；未知到期时间使用短TTL，点击过期重取，不落盘直链。准备中点击共享同一请求；换集/换源/退出取消旧generation。已明确开始播放后的切集/切线保留播放意图与原手动锁定、同集范围。

### 受限运行边界

固定POST `adapters/lumina/sdk`，body仅operation/payload。允许config/channels/banners/catalog/search/detail/play，不暴露通用get/post、host、模块、脚本路径。Python只返回公开内容和媒体字段，raw/plain、认证、内部配置不返回前端。每线程复用Client，进程内共享SDK引擎；指纹在宿主私有目录原子持久化。保持源码算法字节不变，仅部署副本config/profile允许环境绑定。

### 平台打包

Web由同源BFF转固定loopback Python路由，既有媒体网关代理清单/KEY/MAP/分片；修正默认UA覆盖显式空UA的问题。Android将两种引擎映射到JNI目录的liblumafuse.so，Kotlin固定传nativeLibraryDir与私有filesDir，SDK镜像数据提取为真实文件。ARM32不登记Lumina。按用户2026-10-16最新范围，iOS直接不登记Lumina；影视远端地址配置也不隐式启用它，保留旧动漫来源。本轮停止研究iOS本地化，不重写引擎。

### 原布局的数据供给与合并推荐

保留当前首页的分类、二级筛选、搜索/排期、推荐Bento、Hero轮播、继续观看、榜单位置和栏目海报轨。新增SDK内容映射到独立展示模型，携带真实provider/contentId/callback；不能伪造Bangumi ID来复用旧UI。Lumina与旧动漫数据可共同参与栏目，原详情身份与收藏不迁移。主首页不挂载带SDK标题/独立频道条/整页网格的LuminaBrowsePanel。

用户确认榜单改名为“热播推荐”。Mio使用来源真实榜单及原顺序，Lumina使用SDK真实推荐序；并行加载、各自失败/重试、按provider+id去重，展示序号仅为混排位置，保留来源位次，不捏造可比较的热度或七天窗口。条目点击进入对应SDK详情，仍自动准备但不自动播放。

进一步实证：Mio全站目录和全站榜也会全部返回动漫，因此“两个SDK”不等于“动漫与影视”。推荐/热门主推荐区与混合榜单必须分别读取Lumina动漫以及Mio已发现的电影/剧集真实分类。电影/剧集分类ID来自返回元数据，主推荐使用成功完成分类catalog后的匹配条目，榜单使用对应分类hotRank，不以categoryId=0或片名猜测兜底。两类均成功时固定交错分配展示位置，不能被动漫前几项挤掉；晚到分类数据应更新主推荐和榜单scope。动漫tab保留纯动漫及原子分类语义。

### 优化边界

优先减少往返、首屏响应体和重复准备，复用已内置的认证/引擎缓存；不改认证90秒策略、不长缓存短效source/直链、不通过虚假准备成功污染可播放健康度。连接池、算法并行等需要供应商新接口支持时单独评估，不以猴子补丁绕过只改config/profile约束。

## Risks / Trade-offs

- [详情准备会发生真实网络请求] → 设置预算、取消与generation，按需请求首集/当前集，不提前解析整部。
- [短效直链失效] → 仅页面内存短缓存，点击时检查并刷新，保留原headers。
- [SDK无ARM32/iOS引擎] → 两者均不登记Lumina，保持旧来源；不将配置影视远端地址当作Lumina运行能力。
- [共享SDK类型扩展影响旧Mio] → 默认playEpisode委托旧整数play，并覆盖原目录/同集切源回归。
- [旧页面测试把自动打开当作默认] → 更新为准备不打开、点击才恢复真实历史集及进度。

## Migration Plan

导入第三套私有SDK及manifest，按平台打包运行资源；新增提供方为优先项但保留旧规则与数据。代码、桥、模型和页面分片验证。回退仅撤销本变更的新增来源/预解析差异及平台打包，不回滚用户数据。私有vendor和构建输出不提交公共Git。

## Open Questions

用户已确认暂停iOS研究，当前不登记Lumina；不再等待服务地址或Mac操作。本轮聚焦Android/Web原布局渲染和双SDK“热播推荐”，无七天统计字段时不使用该口径。
