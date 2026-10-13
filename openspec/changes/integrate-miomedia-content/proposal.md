## Why
MioMedia SDK 已可调用，但首页影视分类、搜索和详情仍未接入。现场分类路由与分页元数据存在差异，需要以真实参数和独立来源身份接入，避免混入 Bangumi 业务。

## What Changes
- 核验并开放 keyword 搜索与 categoryId 目录过滤，修正分页判断。
- 增加独立字符串 ID 的 MioMedia 内容服务、首页栏目、影视分类与详情入口。
- 详情显示真实线路/剧集，接入提供的自研 playback 模块及现有播放器，处理 ready、ad_required、unavailable。
- 增加独立身份维护命令，成功 negotiate 后才替换身份，广告要求不触发自动身份重建。
- 新版 Web 预览接入运行桥接，媒体复用既有同源网关。

## Capabilities
### New Capabilities
- `miomedia-content-ui`: 分类目录、分页搜索、独立首页与详情以及播放状态边界。
### Modified Capabilities
无。

## Impact
Python 封装、Flutter MioMedia 服务、现代首页与详情路由、新版 Web 预览启动脚本。原有动漫规则、Bangumi ID、追番/历史不变；提供的 SDK 算法字节原样保留。无新增运行依赖，正式环境和广告组件仍待平台资料。
