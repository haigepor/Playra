# MioMedia 内容与播放接入

更新：2026-10-12。项目：`C:/Users/haige/Desktop/Playra`。

在现有 Python HTTP 骨架上接入影视浏览、搜索、资料、线路、剧集和播放。使用本次提供的自研 SDK 播放模块，不在 Flutter 中重写算法。页面沿用现有紧凑深色风格，作品身份与 Bangumi 动漫资料保持独立。

## 调用链与公开操作

`发现/影视搜索 → MioMediaService → SourceRuntimeClient → Web 同源桥接或 Android 配置的 HTTP 服务 → MioMediaSdk → 随包 SDK → 开放平台`

Web：`POST /api/runtime/v1/adapters/miomedia/sdk`。
原生：`POST /v1/adapters/miomedia/sdk`，需要 `X-Kazumi-Request: 1`。
请求仅含 `operation/payload`，不能提交任意地址、脚本、环境配置或会话密钥。

| operation | SDK 请求/能力 | payload | 业务数据 |
| --- | --- | --- | --- |
| recommend | `/home/recommend` | `{}` | `guessYouLike.videos` |
| banners | `/banner/list` | `{}` | `banners` |
| catalog | `/video/categoryList` | `pageIndex/pageSize/categoryId?` | `videos/pageinfo` |
| search | `/video/search` | `keyword/pageIndex/pageSize` | `videos/pageinfo` |
| searchConfig | `/video/searchConfig` | `{}` | 默认关键词、热搜作品元数据 |
| detail | `/video/detail` | `videoId` | `video`，线路位于 `video.player[]` |
| episodes | `/resolve/episodes` | `videoId/code` | 实际编号、名称、线路与 VIP 状态 |
| qualities | `/resolve/qualities` | `videoId/code/episodeNum/caps:[]` | 清晰度及短时换取材料 |
| exchange | `/resolve/exchange` | 上述字段及 `quality/exchangeToken` | 原始换取结果，保留已有受限接口兼容 |
| play | `PlaybackClient.play` | `videoId/code/episodeNum/quality?/caps:[]` | `ready/ad_required/unavailable` |

握手由服务管理，客户端不接收设备密钥。完整文档清单仍见 `miomedia-endpoint-inventory.zh.md`；132 个文档端点不等于本阶段开放的 10 个操作。

## 已核验的分类、分页和搜索

- 目录分页有效字段为 `pageIndex/pageSize`；第 1、2 页返回不同作品。
- 分类过滤有效字段为字符串 `categoryId`；`channelId` 无法达到相同过滤效果。
- 搜索有效字段为 `keyword`；不开放无效的 `wd/keywords` 兼容参数。
- 搜索现场响应出现 `pageinfo.pages=0`，即使 `total` 非零；按 `total`、页号和实际数据判断后续页，并用空页、重复页终止继续加载。
- 未取得可用的独立分类目录接口，不从返回 404 的接口伪造目录。首页从目录和热搜的 `categoryName/categoryId` 发现分类；默认数据只有动漫时，对缺失分类用分类名称发起最多四个首屏搜索，从结果的真实元数据取得分类 ID。发现并发为二，逐栏发布，不穷举全站。仍缺失时显示空状态并允许名称搜索。
- 分类来自真实元数据，不能根据标题猜测。识别动漫、电影、电视剧、综艺、漫剧、短剧和未知类别；首页新增电影、电视剧、综艺、漫剧四组，未知类别不混入已知分类。
- 影视分栏与既有动漫请求独立，目录或热搜先返回即可发布预览；分类请求独立失败、独立重试。
- 新影视栏目目前使用经过核验的目录数据，不将其称为平台热门榜或平台推荐算法结果。

## 页面与播放会话

`lib/services/source/miomedia/miomedia_service.dart` 统一模型和参数。作品 ID 保持字符串，身份为 `miomedia:<id>`，不转换成 Bangumi ID。

发现页接入 `MioHomeController/MioHomeSections`；搜索入口提供动漫搜索和影视搜索。影视搜索支持分页、去重，新关键词清空旧页号并取消旧请求。

`/info/` 根据参数类型进入独立 `MioDetailPage`，保留原 Bangumi 路径。详情使用真实 `playerCode/playerName`，加载资料后先显示剧集；点击剧集才解析播放，不弹出来源选择窗口。

播放器由页面会话复用。切线路取消未完成的解析，旧结果不能覆盖新选择；切集使用真实 `code/episodeNum`。主页面显示当前集附近的 12 集；全部选集弹层约 80% 高度，按 50 集分段，支持升降序和定位当前集。排序只改变显示位置。退出页面释放播放器和请求。

未接入的收藏、讨论、评价、历史和下载能力没有虚假按钮或伪造资料。影视作品不写进动漫收藏，不套用动漫弹幕编号。

### 播放结果

```json
{
  "data": {
    "status": "ready",
    "media": {"url": "<平台媒体地址>", "headers": {}, "format": "m3u8", "name": "<原始名称>"},
    "selection": {"videoId": "<字符串ID>", "code": "<真实线路>", "episodeNum": 12}
  },
  "meta": {"providerId": "miomedia", "operation": "play"}
}
```

- `ready`：校验选择身份后交给现有 `media_kit`。Web 通过 `platformResourceUrl` 和现有同源媒体网关转发来源请求头、HLS 子列表、分片和密钥；Android 使用直链及请求头。
- `ad_required`：播放凭证主路径仍未满足额度时，只返回公开广告要求。应用封装显式使用 `STRATEGY_TOKEN`，每集由 SDK 获取新 nonce 和凭证，再换取播放地址；不自动更换持久设备身份。
- `unavailable`：公开稳定状态，保留手动重试、线路选择。SDK 原始错误可能带上游材料，不返回客户端。

自研客户端解析由 SDK 固定接入点完成，不执行下发脚本，不增加 Lua 运行时。固定解析请求遵守预算、取消检查和响应上限。播放换取与凭证领取会消费令牌或一次性 nonce，网络错误不能自动重提；只读请求最多额外重试一次。`caps=[]`，不声明尚未实现的 `v2ts`。

## 播放凭证与策略

SDK 内部顺序为 `ad/getConfig` → `ad/claimReward` → `resolve/qualities` → `resolve/exchange`，后者提交 `adToken`。桥接只允许固定槽位 `player_switch_episode` 和供给任务 `privilege_supply`；不开放广告事件、奖励或任意凭证操作给客户端。nonce 与凭证不缓存，不返回客户端，不出现在日志或报告中。

应用拥有持久设备态，固定采用 `STRATEGY_TOKEN`；凭证失败返回明确状态，由现有页面提供重试，不自动重置。SDK 的 `STRATEGY_AUTO` 与 `STRATEGY_ROTATE` 保持原样，作为独立诊断/维护客户端的策略，不另写重置循环。

播放结果增加 `strategy`、`rotated` 与单次 `rotations`，既有 `status/media/selection` 保持兼容。`GET /v1/adapters` 的 MioMedia `playbackHealth` 返回进程生命周期内的 `strategy/rotations/attempts/adRequired`；服务重启计数归零。`adRequired` 表示完成 SDK 播放后仍未满足额度的次数，不推断所有网络异常为凭证失效。凭证路径正常时重置次数应为 0。

联调与回滚见 [播放凭证验收记录](verification/miomedia-playback-token.zh.md)。

## SDK 与环境绑定

`tool/source_runtime/vendor/miomedia` 共 12 个文件，10 个与提供的 SDK 字节完全一致。仅 `profile.py/config.py` 增加 TODO，正式接入点、APP_ID、包名、签名及内部配置待平台确认，目前保留默认值联调。校验清单为 `vendor/sdk-manifest.json`。

Python 服务全程标准库。SDK 六层算法与二进制表原样保留，不增加第三方加密库或脚本运行时。内部配置与派生密钥保留在服务内，报告只记录状态。

## 身份与显式维护

首次正常请求生成 `.dart_tool/miomedia/device.json`，服务重启继续复用。会话过期重新 negotiate，严格校验派生密钥一致性、协议/配置版本及 serverTime。

确需维护身份时，先停止对应算法服务，再执行：

```powershell
py -3.13 -B -X utf8 tool/source_runtime/miomedia_identity.py --replace
```

重新生成身份、派生材料并 negotiate；校验成功才原子替换文件，旧文件备份到同目录 `device-before-<时间>.json`，失败保留原文件。输出仅含状态，不打印标识或密钥，无需 Android `pm clear`。命令不开放为 HTTP 操作，不作为广告限制的处理方案；服务重启后读取新身份。

管理员可用 `PLAYRA_MIOMEDIA_STATE_DIR` 指定身份目录。当前作用域为一个本地服务；正式多用户部署仍需鉴权和身份隔离。

## 启动与测试

使用 PowerShell 7，两个终端分别启动：

```powershell
Set-Location 'C:\Users\haige\Desktop\Playra'
py -3.13 -B -X utf8 tool/source_runtime/server.py --port 8945
```

```powershell
Set-Location 'C:\Users\haige\Desktop\Playra'
.\tool\start-web.ps1 -Port 8936 -RuntimePort 8945 -Build -NoOpen
```

Web 使用当前站点同源 `/api/runtime/v1/`。旧 Web 服务不会自动启用桥接，需用新端口或重启对应服务。

新版移动页面的浏览器验收使用已有独立预览入口：`.\tool\start-home-preview.ps1 -Port 8937 -RuntimePort 8945 -Build -NoOpen`。普通 `main.dart` 的 Web 入口保留其既有旧版导航策略；独立预览才强制新版界面。

Android 调试沿用 HTTP 骨架：`adb reverse tcp:8945 tcp:8945`，构建时传 `-RuntimeUrl 'http://127.0.0.1:8945/v1/' -RuntimeAllowHttp`，见 `source-algorithm-runtime.zh.md`。该地址依赖 USB 转发，不是独立安装的正式服务地址；正式移动端部署需可达的 HTTPS 服务和鉴权。

脱敏内容/媒体联调：

```powershell
py -3.13 -B -X utf8 tool/source_runtime/miomedia_content_check.py
```

检查在 `.dart_tool/miomedia-content-validation` 持久复用独立测试身份，不因广告或失败换身份。报告只含状态、字段名、分页/分类一致性及媒体类型，没有媒体令牌或密钥。实际播放须同时满足 `ready`、HTTP 200、正确类型与 HLS 内容；HTTP 200 的 HTML 不算成功。已验证直链没有开放 CORS，浏览器必须使用同源媒体网关。

## 修改范围与回滚

- Python：受限操作与播放封装、显式身份维护、脱敏联调、随包 SDK 和校验清单。
- Flutter：新增 MioMedia 服务、首页控制器、浏览和详情页；现有 `discover_page.dart/modern_home_view.dart/info_module.dart` 接入入口。
- Web 启动：`download_directory_service.dart` 使用现有平台 IO 适配层，防止原生 `Platform` 调用中断 Web 启动。
- `start-home-preview.ps1` 增加可选 `RuntimePort`，使已有新版页面预览与正式 Web 一样接入受限桥接。
- 测试、接入文档和 `integrate-miomedia-content` OpenSpec 契约同步。

受影响文件的实施前备份在 `.dart_tool/miomedia-playback-before-20261012`，旧 SDK 目录为其中 `vendor-m before`，下载目录服务另有单文件备份。回滚仅恢复本阶段相关文件、移除本阶段新增文件，保留其他既有修改。身份按需单独备份，不随源码回滚重建。
