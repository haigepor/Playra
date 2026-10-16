## Why

现有动漫由 AniFive 四条规则及 Bangumi 资料组成，不能提供 Lumina 的原生频道、列表、详情和播放链。用户要求以 Lumina 数据和解析优先，同时进入详情自动准备直链但等待点击播放，保留现有来源及历史收藏。

## What Changes

- 新增受限 Lumina Python Adapter、私有 SDK 导入/完整性记录及 Dart 内容服务，供应商算法和协议原值不改。
- 动漫频道、浏览、搜索和独立详情优先使用 Lumina；不可用时保留既有动漫入口，影视继续使用 MioMedia。
- 扩展共享 SDK 分集契约以保留真实字符串 part，不将供应商视频 ID 冒充 Bangumi ID。
- 将准备直链与打开播放器分离：进入详情自动解析，用户点击才打开；换集/换线取消旧准备，短效地址过期刷新。
- Web 使用同源固定 BFF；Android arm64/x86_64 使用 Chaquopy + 只读 JNI 原生库；ARM32 不登记 Lumina。按用户最新范围，iOS不登记未具备运行条件的Lumina，保留旧动漫来源，暂停本地/远端Lumina研究。
- 首页继续使用原推荐卡、轮播、栏目海报轨及现有样式token；SDK只提供数据与真实点击身份，不新增品牌大面板替换原布局。
- 动漫与影视SDK真实内容共同渲染“热播推荐”，保留各来源顺序和身份，不虚构未经接口证实的七天统计窗口。
- 补充取消、媒体头、身份持久化、来源优先级、准备状态及旧行为回归，并按平台记录未执行项。

## Capabilities

### New Capabilities

- `lumina-anime-content`: 优先动漫内容、受限接口、原始作品/分集身份及平台能力边界。
- `prepared-detail-playback`: 自动解析但不自动播放的详情状态机、短效缓存及明确播放意图。

### Modified Capabilities

无已归档主规范需要修改；现有 SDK 接入规范随实现同步更新。

## Impact

涉及 Python runtime/固定路由、私有输入导入、Android JNI 打包、共享 SDK 类型和协调器、动漫首页/搜索及两类详情页。不新增 Python 第三方依赖；不执行账号、广告或设备桥部署；不迁移或清空旧历史/收藏/自定义规则。新增 Lumina 作品不伪造旧资料身份，本轮不新增独立 SDK 收藏库。
