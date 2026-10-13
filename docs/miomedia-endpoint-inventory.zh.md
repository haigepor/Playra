# MioMedia 接口与数据清单

更新：2026-10-12。依据提供的全部接口文档去重整理。

共 **132 个明确端点：130 个 POST、2 个 GET**。这是文档端点数，不能等同于已验证可用数。SDK 的通用 request 方法也不表示所有参数已得到核验。

本阶段公开 7 个 SDK 内容操作，握手为内部调用，共验证 8 个上游路径。其余接口保留文档状态；本轮没有尝试账户、支付、会员、广告奖励、评论发布等写操作。

## 数量概览

| 分组 | 去重数量 | 数据范围 |
| --- | ---: | --- |
| 认证与设备 | 20 | 设备与会话、登录、密码、验证码 |
| 内容与目录 | 27 | 推荐、轮播、分类、作品详情、搜索、日历、评论评价、历史 |
| 播放与下载 | 13 | 剧集、清晰度、播放材料与下载凭证 |
| 会员与任务 | 20 | 会员等级、钱包、签到任务与福利 |
| 社区互动 | 26 | 讨论、弹幕、影评、收藏与互动 |
| 用户与消息 | 15 | 用户资料、通知、反馈、气泡皮肤 |
| 广告 | 8 | 槽位、配置、签名、事件与奖励状态 |
| 客户端配置与更新 | 3 | 配置读写与版本检查 |

## 响应与适配注意

- 上游先解密得到业务包络 `code/success/msg/data`，HTTP 200 不保证业务成功。
- 标为 PASS 的项目均同时检查业务成功与解密。播放材料成功不代表已得到可播放媒体。
- 作品 ID 是字符串，勿转换成 Bangumi ID；作品分类也需按实际字段映射，不能将全部数据归为电影。
- data 中具体字段随端点而异。文档只给用途的端点，本清单不补造响应 schema。
- POST 主前缀为 `/api/v1/app/client`。`auth/bootstrap.jpg` 为同前缀 GET；`check-update` 是另一接入点的 `/api/v1/client/check-update`。

## 认证与设备

| 方法 / 端点 | 用途与已知数据 | 验证状态 |
| --- | --- | --- |
| `POST auth/bindEmail` | 绑定邮箱 | 仅文档，未联调 |
| `GET auth/bootstrap.jpg` | 会话配置资源；内嵌 masterSecret/signSecret/b64tTable/fpAlgo/keyVersion/configVersion；本轮未实现下载装配 | 仅文档，未联调 |
| `POST auth/changePassword` | 修改密码 | 仅文档，未联调 |
| `POST auth/defaultAvatars` | 默认头像列表 | 仅文档，未联调 |
| `POST auth/exchangeLegacyToken` | 旧版令牌兑换 | 仅文档，未联调 |
| `POST auth/generateCaptcha` | 生成人机验证 | 仅文档，未联调 |
| `POST auth/listEmailWhitelist` | 邮箱白名单 | 仅文档，未联调 |
| `POST auth/login` | 登录 | 仅文档，未联调 |
| `POST auth/negotiate` | 设备登记、派生密钥一致性、serverTime、algorithms、protocol、keyVersion；本轮 PASS，内部调用 | PASS（默认环境） |
| `POST auth/passwordPolicy` | 密码策略 | 仅文档，未联调 |
| `POST auth/refreshToken` | 刷新令牌 | 仅文档，未联调 |
| `POST auth/register` | 注册 | 仅文档，未联调 |
| `POST auth/resetPassword` | 重置密码 | 仅文档，未联调 |
| `POST auth/sendVerifyCode` | 发送验证码 | 仅文档，未联调 |
| `POST auth/status` | 登录态查询 | 仅文档，未联调 |
| `POST auth/verifyCaptcha` | 校验人机验证 | 仅文档，未联调 |
| `POST device/delete` | 注销设备 | 仅文档，未联调 |
| `POST device/heartbeat` | 设备心跳 | 仅文档，未联调 |
| `POST device/list` | 登录设备列表 | 仅文档，未联调 |
| `POST device/setPrimary` | 设为主设备 | 仅文档，未联调 |

## 内容与目录

| 方法 / 端点 | 用途与已知数据 | 验证状态 |
| --- | --- | --- |
| `POST banner/list` | data.banners：轮播列表；本轮返回 20 条 | PASS（默认环境） |
| `POST calendar/schedule/calendar` | 新片周历 + 每日更新列表 | 仅文档，未联调 |
| `POST category/filter/dimensions` | 筛选维度 | 仅文档，未联调 |
| `POST category/type/listActive` | 启用分类 | 仅文档，未联调 |
| `POST category/types` | `{types:[{id,name,code,icon,...}]}` | HTTP 404（上一轮默认环境） |
| `POST category/videos` | 分类视频列表 | 仅文档，未联调 |
| `POST guide/listActive` | 引导位 | 仅文档，未联调 |
| `POST history/list` | 分页 | 仅文档，未联调 |
| `POST history/report` | 进度上报 | 仅文档，未联调 |
| `POST home/modules` | `{list:[{id:"MOD_818368",name:"七天热播榜",k:"hot",layout:"strip",...}]}` | 仅文档，未联调 |
| `POST home/recommend` | data.guessYouLike：title/videos/hasMore/pageinfo；本轮返回 10 个作品 | PASS（默认环境） |
| `POST splash/active` | 开屏配置 | 仅文档，未联调 |
| `POST video/categoryList` | data.videos/pageinfo：默认作品列表；本轮返回 10 条，分页/分类筛选语义待核验 | PASS（默认环境） |
| `POST video/comments` | 当前剧集讨论列表 comments：用户昵称、头像、内容、点赞数、回复数等 | 仅文档，未联调 |
| `POST video/detail` | data.video：作品 ID、标题、分类、简介、封面、评分、集数/更新信息；线路为 video.player | PASS（默认环境） |
| `POST video/engagement-counts` | 互动计数 | 仅文档，未联调 |
| `POST video/guessLike` | 猜你喜欢列表 | 仅文档，未联调 |
| `POST video/idMapping` | 文档仅列出 ID 映射端点；映射方向与请求/响应结构待核验 | 仅文档，未联调 |
| `POST video/modules` | 栏目配置 | 仅文档，未联调 |
| `POST video/reviews` | 整部作品评分分布与影评列表；完整请求及分页结构待核验 | 仅文档，未联调 |
| `POST video/schedule` | 播出时间表 | 仅文档，未联调 |
| `POST video/search` | 关键词搜索 | 仅文档，未联调 |
| `POST video/searchConfig` | 搜索配置（热搜词等） | 仅文档，未联调 |
| `POST video/searchSuggest` | 搜索建议 | 仅文档，未联调 |
| `POST video/similar` | 同类推荐 | 仅文档，未联调 |
| `POST video/stats` | `{items:[{videoId,likeCount,favoriteCount}]}` | 仅文档，未联调 |
| `POST video/subscribe` | 追番/订阅 | 仅文档，未联调 |

## 播放与下载

| 方法 / 端点 | 用途与已知数据 | 验证状态 |
| --- | --- | --- |
| `POST diagnostic/play` | 播放诊断 | 仅文档，未联调 |
| `POST download/batch/order` | 批量下载排序 | 仅文档，未联调 |
| `POST download/cacheList` | 缓存列表 | 仅文档，未联调 |
| `POST download/credential/claim` | 领取下载凭证 | 仅文档，未联调 |
| `POST download/credential/release` | 释放下载凭证 | 仅文档，未联调 |
| `POST download/credential/renew` | 续期下载凭证 | 仅文档，未联调 |
| `POST download/episodes` | 可下载剧集 | 仅文档，未联调 |
| `POST download/quota` | 下载配额查询（配额与会员等级相关） | 仅文档，未联调 |
| `POST download/resolve` | 下载地址解析 | 仅文档，未联调 |
| `POST resolve/episodes` | data.episodes：episodeNum/episodeName/displayName/sourceId/code/isVip；本轮一条线路 288 集 | PASS（默认环境） |
| `POST resolve/exchange` | data.playUrl/quality/expiresIn/isClientParse/luaScript/originalUrl；本轮空直链、需客户端解析 | PASS（默认环境） |
| `POST resolve/qualities` | data.qualities/exchangeToken/expiresAt/isClientParse；实际返回 1080p 项 | PASS（默认环境） |
| `POST resolve/sign` | 播放签名 | 仅文档，未联调 |

## 会员与任务

| 方法 / 端点 | 用途与已知数据 | 验证状态 |
| --- | --- | --- |
| `POST coin/records` | 金币流水 | 仅文档，未联调 |
| `POST membership/catalog` | 会员等级全量表 | 仅文档，未联调 |
| `POST signIn/rewardPreview` | 签到奖励预览 | 仅文档，未联调 |
| `POST task/complete` | 完成任务 | 仅文档，未联调 |
| `POST task/config` | 任务配置 | 仅文档，未联调 |
| `POST task/list` | 任务列表 | 仅文档，未联调 |
| `POST task/reportShare` | 分享上报 | 仅文档，未联调 |
| `POST task/signIn` | 每日签到 | 仅文档，未联调 |
| `POST task/subscribe` | 任务订阅 | 仅文档，未联调 |
| `POST task/watch-progress` | 观看进度任务上报 | 仅文档，未联调 |
| `POST task/watch-progress/status` | 观看进度任务状态 | 仅文档，未联调 |
| `POST vip/info` | 当前会员状态 | 仅文档，未联调 |
| `POST vip/redeem` | 卡密兑换 | 仅文档，未联调 |
| `POST vipCenter/info` | 会员中心汇总 | 仅文档，未联调 |
| `POST vipCenter/plans` | 开通套餐 | 仅文档，未联调 |
| `POST wallet/info` | 金包余额 | 仅文档，未联调 |
| `POST welfare/bindInviteCode` | 绑定邀请码 | 仅文档，未联调 |
| `POST welfare/claim` | 领取福利 | 仅文档，未联调 |
| `POST welfare/hub` | 福利中心 | 仅文档，未联调 |
| `POST welfare/inviteInfo` | 邀请信息 | 仅文档，未联调 |

## 社区互动

| 方法 / 端点 | 用途与已知数据 | 验证状态 |
| --- | --- | --- |
| `POST comment/create` | 发表评论 | 仅文档，未联调 |
| `POST comment/danmaku` | `{list:[{time,type,color,author,text,id,likes,fontSize,skinId,...}]}` | 仅文档，未联调 |
| `POST comment/danmaku/delete` | 删除弹幕 | 仅文档，未联调 |
| `POST comment/danmaku/report` | 举报弹幕 | 仅文档，未联调 |
| `POST comment/danmaku/send` | 发送弹幕 | 仅文档，未联调 |
| `POST comment/delete` | 删除评论 | 仅文档，未联调 |
| `POST comment/list` | 评论列表（也可用 `video/comments`） | 仅文档，未联调 |
| `POST comment/my` | 我的评论 | 仅文档，未联调 |
| `POST comment/replies` | 评论回复列表 | 仅文档，未联调 |
| `POST comment/report` | 举报评论 | 仅文档，未联调 |
| `POST episode/like` | 剧集点赞 | 仅文档，未联调 |
| `POST episode/like-count` | 剧集点赞计数 | 仅文档，未联调 |
| `POST episode/liked-status` | 剧集点赞状态 | 仅文档，未联调 |
| `POST favorite/batchDelete` | 批量删除 | 仅文档，未联调 |
| `POST favorite/create` | 添加收藏 | 仅文档，未联调 |
| `POST favorite/delete` | 删除收藏 | 仅文档，未联调 |
| `POST favorite/list` | 收藏列表 | 仅文档，未联调 |
| `POST favorite/status` | 收藏状态 | 仅文档，未联调 |
| `POST interaction/liked-status` | 互动状态查询 | 仅文档，未联调 |
| `POST interaction/operate` | 互动操作（点赞等） | 仅文档，未联调 |
| `POST review/delete` | 删除影评 | 仅文档，未联调 |
| `POST review/like` | 点赞影评 | 仅文档，未联调 |
| `POST review/list` | 影评列表（评分分布 Excellent/Good/Fair/Average/Poor 也可用 `video/reviews`） | 仅文档，未联调 |
| `POST review/report` | 举报影评 | 仅文档，未联调 |
| `POST review/submit` | 提交影评（含评分） | 仅文档，未联调 |
| `POST review/summary` | 影评汇总 | 仅文档，未联调 |

## 用户与消息

| 方法 / 端点 | 用途与已知数据 | 验证状态 |
| --- | --- | --- |
| `POST bubble-skin/catalog` | 气泡皮肤目录 | 仅文档，未联调 |
| `POST feedback/list` | 我的反馈 | 仅文档，未联调 |
| `POST feedback/replies` | 反馈回复 | 仅文档，未联调 |
| `POST feedback/reply` | 回复反馈 | 仅文档，未联调 |
| `POST feedback/submit` | 提交反馈 | 仅文档，未联调 |
| `POST feedback/types` | 反馈类型 | 仅文档，未联调 |
| `POST notice/messages` | 消息列表 | 仅文档，未联调 |
| `POST notice/popup/list` | 弹窗公告列表 | 仅文档，未联调 |
| `POST notice/popup/read` | 弹窗公告已读 | 仅文档，未联调 |
| `POST notice/read` | 标记已读 | 仅文档，未联调 |
| `POST notice/sessions` | 会话列表 | 仅文档，未联调 |
| `POST notice/subscriptionFeed` | 订阅动态 | 仅文档，未联调 |
| `POST notice/unreadCount` | 未读计数 | 仅文档，未联调 |
| `POST updateProfile` | 更新资料 | 仅文档，未联调 |
| `POST userInfo` | 用户信息 | 仅文档，未联调 |

## 广告

| 方法 / 端点 | 用途与已知数据 | 验证状态 |
| --- | --- | --- |
| `POST ad/claimReward` | 奖励领取；返回 granted/rejected；需要真实业务条件 | 仅文档，未联调 |
| `POST ad/getConfig` | 广告配置：appKey/enable/nonce/rewardEligible/slots | 仅文档，未联调 |
| `POST ad/getRewardStatus` | 奖励状态；完整字段待核验 | 仅文档，未联调 |
| `POST ad/getSignature` | 广告展示签名：signature/expiresIn/shouldShow/remainingToday/denyReason | 仅文档，未联调 |
| `POST ad/getSlots` | 广告槽位列表：slotCode/placementId/minWatchSeconds/allowEarlyClose/s2sVerify | 仅文档，未联调 |
| `POST ad/reportClose` | 关闭广告上报；返回 status/message/amount | 仅文档，未联调 |
| `POST ad/reportEvent` | 展示/错误等广告事件上报；返回 status | 仅文档，未联调 |
| `POST ad/reportNoFill` | 无填充事件上报；返回 status | 仅文档，未联调 |

## 客户端配置与更新

| 方法 / 端点 | 用途与已知数据 | 验证状态 |
| --- | --- | --- |
| `GET check-update` | 客户端版本信息；使用独立更新接入点，字段待核验 | 仅文档，未联调 |
| `POST config/batchSet` | 客户端配置读写（见[认证与账户](auth.md)） | 仅文档，未联调 |
| `POST config/resolve` | 客户端配置读写（见[认证与账户](auth.md)） | 仅文档，未联调 |

## 实际响应与文档差异

1. `category/types` 上一轮返回 HTTP 404，不能视为完整分类能力已可用。
2. `video/detail` 实际线路在 `data.video.player`，并未返回文档描述的同层 episodes。
3. `resolve/episodes` 实际剧集位于 `data.episodes`。上一轮一次读取中断后重试成功；封装现有有限网络重试。
4. `resolve/exchange` 当前返回客户端解析模式和空 playUrl，需要后续解析能力；本轮仅保留真实数据。

机器清单：`docs/miomedia-endpoint-inventory.json`。提取工具：`tool/source_runtime/endpoint_inventory.py`；人工核验的用途补充与现场记录在本交付清单中。
