## Context
XL 跨 SDK、内容模型与 Flutter 页面，拆为参数核验、内容接入、自研播放和跨平台验证。SDK 算法不动。现场 categoryId 过滤有效，channelId 被忽略；keyword 有效，wd/keywords 无效。搜索 pages=0 但分页有效。分类独立路由 404。
## Goals / Non-Goals
**Goals:** 独立字符串作品身份、元数据分类、分页搜索、现代首页影视栏目与详情。首页请求逐栏发布，动漫请求不等待影视源。
**Non-Goals:** 把 MioMedia ID 填入 Bangumi/Hive、账号写操作、广告伪造、Lua 任意执行、宣称未核验媒体已能播放。
## Decisions
1. 增加 MioMedia 专属内容服务和模型，复用 SourceRuntimeClient。categoryName/types 精确类别证据映射；未知类保留未知，不从标题猜分类。
2. 分类目录缺失时从首页目录及热搜的真实分类字段发现分类 ID；默认数据只有动漫时，用缺失分类名称执行最多四个首屏搜索，两个发现任务逐栏发布。分类仍来自响应元数据，不从标题猜测，也不穷举全站。具体分类请求使用实际发现的 categoryId，缺失映射显示空状态。
3. pageIndex/pageSize 分页根据 total 或真实返回数量判断；检测重复页避免无限翻页。搜索对 keyword 编码，支持请求取消和陈旧响应隔离。
4. MioMedia 首页视图独立于 Bangumi 卡片和收藏/历史。影片入口携带 MioMedia 类型参数，info 路由判别后进入独立详情。保持同一暗色主题与紧凑控件。
5. 详情先显示资料，再独立获取选中线路剧集；真实 episodeNum，不按显示位置猜身份。2026-10-12 用户提供新版自研 playback 模块，原样替换并通过 Python 服务返回 ready/ad_required/unavailable；复用项目已有 media_kit，播放器会话不依赖 Bangumi 编号。
6. 自研 playback.resolve 按 SDK 固定解析入口完成解析，不执行远程 Lua。PlaybackClient 明确 rotate_on_ad=False，广告要求保持真实状态。身份重建是显式本地维护命令，先校验 negotiate，备份后原子替换，不作为播放重试分支。
7. Web 媒体缺少 CORS，复用现有 platformResourceUrl 同源网关处理 HLS 资源；原生仍使用直链与媒体请求头。现有独立新版浏览器预览新增可选 RuntimePort，不改变普通 Web 入口的导航策略。
8. 换取消费令牌，网络失败不自动重提 exchange；只读操作保留预算内有限重试。长篇选集按真实编号分段，主页面只渲染附近 12 集，全选集弹层使用按需构建网格。
## Risks / Trade-offs
- 影视分类页沿用动漫视觉层级：真实 types/tags 题材筛选、来源推荐/原始评分精选卡片、口碑与两个题材栏目、猜你喜欢。猜你喜欢复用已验证的 categoryId 分页，尾部向下滚动自动加载，保留取消、重复页检测与失败手动重试；SliverGrid 按需构建。筛选仅针对已加载目录，不穷举全站；新增页继续应用相同题材。
- 2026-10-12 现场核验 home/modules、category/filter/dimensions、category/type/listActive、category/types、video/guessLike 均为 HTTP 404。七天榜单显示未提供统计的空状态，不能以总 playCount、评分或默认顺序生成近七天排行；不暴露未核验的筛选参数或额外 SDK 操作。
- [目录没有分类列表] → 从已加载条目发现，缺失映射可空；记录结果，不穷举整个站点。
- [存在4031] → 对要求广告的资源显示真实限制；验证可用 ready 路径与 ad_required 分支，正式广告组件尚待平台接入。
- [外部服务未启动] → 页面错误可重试，动漫仍正常；默认地址沿用已有配置。
## Migration Plan
无用户数据迁移；最新实施前副本与基线位于 `.dart_tool/miomedia-playback-before-20261012/`。只回滚本轮差异，不还原已有工作区。Web 下载目录初始化改用现有平台 IO 适配层，避免原生 Platform 调用中断启动。
## Open Questions
广告正式组件与正式环境参数仍需平台资料；新版自研解析已补齐，可以独立接入验证。
