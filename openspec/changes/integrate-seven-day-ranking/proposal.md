## Why

新版影视分类页仍显示榜单空状态。接入方已核验 `video/modules` 中的 `MOD_818368`，可以展示真实榜单，不再把累计播放量或评分当作七天热度。

## What Changes

- 原样同步提供的 SDK ECSM 传输实现及导出，不重写算法，不更换持久设备身份。
- 同步 SDK 已提供的纯标准库加速 suite，对旧版进行向量与同一真实响应速度对照。
- Python 受限桥接增加 `hotRank`，只请求 `/video/modules`，必填字符串 categoryId、从 1 起算的 pageIndex、pageSize；投影目标栏目前十，减少大响应转发。
- Flutter 增加保留服务端标题和原始位次的榜单模型、分类独立缓存与独立加载/错误/空状态。
- 推荐、热门使用 categoryId `0`；分类使用已有真实元数据 ID。没有对应来源分类时不借用全站榜单。动漫子分类按真实名称映射，不混用 Bangumi ID。
- 展示带位次的竖版卡片，点击进入已有 MioMedia 详情/播放器；分页、题材筛选不会过滤或重排榜单。
- 按用户追加要求统一选集卡片三档布局：短名紧凑格、中名两列、长名单行宽卡（最多两行）；分段使用平滑滑块，保持真实剧集编号。

## Capabilities

### New Capabilities
- `seven-day-ranking`: 服务端栏目顺序与标题保真、分类隔离、渐进加载和只读联调验收。
- `episode-card-layout`: 页面与弹层共享三档文字布局及平滑分段选择。

### Modified Capabilities
无。

## Impact

影响 Python SDK 适配器、MioMedia 数据服务、首页控制器和榜单展示。Web 与 Android 共享 Flutter 实现及现有 HTTP 桥接；无新依赖、无密钥下发、无广告/身份重试变更。需运行加载新代码的 Python 服务，保留原设备文件。
