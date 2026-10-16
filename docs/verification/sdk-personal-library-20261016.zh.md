# SDK 统一历史收藏、解析恢复与详情布局验收

2026-10-16。范围与回退见[实施约定](../development/sdk-personal-library-plan.zh.md)，契约见[统一接入规范v1.8](../development/source-sdk-onboarding.zh.md)。本轮未提交、推送，保留整轮接入的未提交改动。

## 交付行为

- AniFive及旧在线/缓存历史、Bangumi收藏、自定义规则原样保留。Lumina/MioMedia按真实providerId/contentId建立本地个人库，不制造Bangumi身份。
- 支持CollectType各状态、逐集位置/时长/真实part、原线路/手动锁/画质偏好。收藏和历史互不删除；只准备不记历史，隐私模式不更新历史。
- 实际媒体就绪后记录，5秒检查、暂停/切媒体/后台/退出补写；无变化不重复写。序列化队列保留交错的收藏与进度，失败可见且不阻塞重试。
- 首页继续观看、历史日期分组/搜索/在线缓存筛选、新版追番状态/搜索/排序统一展示。SDK缺评分/开播日不伪造数值；原记录排序相同时保持原顺序。
- 续播重取目录及短效链接；先准备，点击再打开媒体，按时长校验seek。原手动线路/集消失提示选择，不静默首集。近结尾进度保留，重新打开已完成集从头播放。
- 本轮仅各端本地持久，未扩展旧Bangumi/WebDAV同步协议或云同步/导出格式。

## 自动验证

| 项目 | 已执行结果 |
|---|---|
| 完整Flutter回归 | 755/755通过，包含异步seek短暂0、业务解析失败及手动锁保护回归 |
| Python宿主回归 | 123/123通过，纯文本业务拒绝与未知坏响应分类隔离、不泄露上游内容 |
| 模型JS编译执行 | 实际SdkWatchProgress编译JS后在V8通过：positionMs=754321、durationMs=1415000、原始part/锁保持 |
| 专项持久化/界面 | 同ID不同SDK、特殊集、重开Hive、互删独立、并发写入、隐私切换、失败后重试、坏记录隔离、待播第99集和线路锁通过 |
| 静态分析 | 全量无error/warning，54项info；最终范围无error/warning，13项info（语句花括号风格） |
| 平台回归 | 原历史、收藏同步、AniFive身份/自定义规则等包含在全量回归中；没有改旧Hive类型/规则资产 |

Web实测发现`1 << 50`在JS产物成为0，导致反序列化position/duration被clamp为0；改用明确数值上限31536000000毫秒，并分离纯模型用于JS编译回归。发现时原始JSON存储含真实进度，不清库修复。另修复自定义收藏按钮的button语义。直接Flutter Chrome测试运行器未完成加载，已终止，不记为通过；纯模型JS回归及最终正式页面实际刷新续播分别验证。

## 最终两端运行证据

Web实际地址为本地BFF正式构建页面`http://127.0.0.1:18962/`；安卓为雷电同一设备`127.0.0.1:5555`，使用`install -r`覆盖安装、`am force-stop`后重新启动；没有卸载或清库。

| 样本/流程 | 实际证据 |
|---|---|
| Web Lumina《沧元图》第99集 | 首次4K真实3840×1776/解码帧递增；暂停27.871111秒、刷新后继续观看显示0:27，准备时无VIDEO；点击后恢复31.327822秒；后续保存55.499595秒，再次刷新/点击后58秒继续，暂停最终79.067399秒，页面1:19 |
| Web MioMedia《毒液：最后一舞》 | 正片实际1920×1080，15.298629秒/371帧/error为空；暂停17.891738秒，刷新后仍0:17；收藏在看保存并与Lumina同时展示。后续原线路加载慢自动回退，实际备用HLS1920×808出画；由此发现晚出画历史缺口并追加修复/专项复验 |
| Android Lumina《沧元图》第99集 | 实际3840×1776；保存70.400秒，覆盖安装和进程重启后1:10仍在；点击播放72.520秒继续。再保存144秒，最终构建准备时仍第99集/2:24/NONE，点击后153.800秒，暂停162.840秒，历史/收藏均2:42 |
| Android MioMedia《唐探1900》 | 实际3840×1608，保存9.133秒；覆盖安装重启后0:09仍在；从收藏继续后31.250秒，暂停49.183秒，收藏页变为0:49 |
| 混合历史/收藏 | Web搜索Lumina实际找到1条、清除恢复2条，动漫/电影均可管理收藏；在看→想看筛选正确。安卓历史共5条=新SDK2条+原历史3条，画面同时出现DM84/akianime旧记录，原首页《航海王》第68集10:24仍保留；收藏页2部，SDK来源徽标与真实集/进度可读 |

只准备/主动收藏不会生成观看历史，当前目录与旧进度均可在未起播状态查看。实际视频裁边宽高原样报告，不把3840×1776/3840×1608写成实际2160高。旧收藏基线为空，本次没有声称恢复了不存在的旧收藏；旧收藏/同步兼容由全量回归覆盖。测试新增的SDK样本记录/收藏保留在验收环境。

本机忽略目录`.dart_tool/lumina-integration-20261016/`保留脱敏证据：`personal-complete-tests.log`、`personal-final-scope-analyze.log`、`web-personal-history-search.png`，以及`android/personal-final-history-mixed.json`、`personal-final-library-settled.{png,json}`、`personal-final-anime-paused.json`、`personal-final-movie-resume-verified.json`。截图在动画结束后复核；两端最终停止播放。Web仍有外部封面/Bangumi代理错误，不宣称零控制台错误。

修复追加：原生/MP4 seek Future可能早于位置流，使用SdkResumeProgressGuard禁止瞬时0覆盖旧进度，位置确认后仍允许用户主动倒回片头；HLS实际时钟可能早于视频尺寸回报，记录身份在媒体安装时绑定，正进度/时长确认后保存，并按同一时长容差处理迟到的续播恢复。准备状态没有媒体，因而不会误记为观看。

## 最新解析与布局复验

《毒液：最后一舞》稳定线路连续两次返回HTTP 200纯文本“解析播放地址失败！”。此前被SDK按JSON解析失败归类；宿主现在识别该确知业务拒绝为CLIENT_PARSE_REJECTED，原SDK算法/常量不修改，未知坏响应仍为CLIENT_PARSE_INVALID_RESPONSE。不能把第三方没有提供地址宣称为已修复资源本身。

同作品高速线路实际返回MP4、媒体HTTP 206/video/mp4、头部ftyp；备用线路1返回HLS、媒体HTTP 206/application/vnd.apple.mpegurl、头部EXTM3U。错误栏直接打开线路选择，不擅自解除手动锁、不跳首集。未知画质不再声称已使用原始直链，也不展示没有其他档位的自动单选。收藏并入播放源栏、历史摘要缩为单行，画质标签与真实档位同排，错误栏和选集间距收紧，沿用ModernPlayerScope色彩/字体/48触控约束。旧媒体保留时，其分辨率只在身份/线路/分集仍相符时用于当前线路摘要。

独立Web验证端口18963（BFF）/18966（Python）使用同一正式Web构建。旧18962服务及数据保持。新端口实测：稳定线路准确显示无资源提示及切换入口，VIDEO为空；显式选备用线路1后仅准备，点击播放才出画1920×808、573帧，暂停23.708224秒；收藏在看、刷新后继续观看HD中字0:23，详情仍手动备用线路1、无VIDEO；点击恢复23.708秒并推进到34.827726秒/326帧，最终暂停0:57。晚出画HLS不再停留在旧0:17。

最终运行包覆盖安装、强停重启后安卓仍保留2部SDK收藏，Mio《唐探1900》由49.183秒续播59.100秒，暂停69.416秒；Lumina第99集由339.760秒续播343.600秒，实际3840×1776，暂停352.880秒。旧历史3条及自定义规则不清理。安卓仅雷电x86_64，实体手机/iOS本轮未执行。

安卓追加原报错同作品核验：《毒液：最后一舞》手动稳定线路出现业务无资源提示，错误栏切换到高速线路、点击播放实际1920×1080，暂停14.250秒；最终APK覆盖安装和进程重启后从首页继续观看恢复手动高速线路、0:14，点击后15.875秒继续，暂停21.125秒。最终Web构建同样由0:57继续到63.232614秒/1920×808/203帧；再次切到失败的稳定线路后摘要回到“画质待确认”，不沿用旧HLS分辨率。

已检查桌面与390窄屏的实际布局、锁线、恢复入口及播放；320px/放大字体由界面回归覆盖。浏览器在桌面缩放后直接更改viewport曾保留旧Flutter DPR，窄屏刷新后Flutter容器与390px视口一致；该次过渡截图不作为布局通过依据。外部封面/番组代理仍有控制台错误，不宣称零错误。

## 最终构建与交付物

- APK：`build/app/outputs/flutter-apk/app-release.apk`，2.3.8+20308，124696386字节，SHA256 `83f769f9b2452e34f70a56af7a207b1827f90f6097da9236a830cb9aa6468a27`。
- 最新Web构建52.3秒，APK Gradle75.1秒；本地BFF提供main.dart.js为HTTP200，响应SHA256与构建文件一致。
- 完整755项通过后，分辨率显示身份校验的小补丁再执行14项相关回归全部通过；最终页面analyze无error/warning，8项花括号info。APK ZIP CRC、v2签名、引擎可加载段/SDK模块及资产摘要通过；Lumina私有SDK完整性验证通过。
- 最终包已用install -r覆盖安装并重启，不卸载、不清库。两端播放最终暂停。旧18962服务未停止；18963/18966仅为本轮独立验收服务，未对公网部署。
- 证据：忽略目录内`parse-layout-full.log`、`parse-layout-python.log`、`parse-layout-final-focused.log`、`parse-layout-final-web.log`、`parse-layout-final-apk.log`、`web-final-error-mobile.png`及`android/parse-layout-final-venom-*.json`。文件清单与回退范围见下表。

## 本轮文件与回退

| 文件/目录 | 目的与影响 |
|---|---|
| lib/services/storage/sdk_library_models.dart | 稳定身份、真实part、进度/收藏版本化JSON；纯模型可JS对拍 |
| lib/services/storage/sdk_library_store.dart | 独立个人库、隐私检查、串行持久写入、历史收藏独立删除 |
| lib/services/storage/storage.dart | 只增加sdk_personal_library_v1 Box初始化 |
| lib/presentation/modern/pages/sdk_player_detail_page.dart | 实播记录、生命周期补写、收藏菜单、历史选集/锁/进度恢复 |
| lib/presentation/modern/player/sdk_quality_selector.dart | 紧凑画质行，未知档位移除无效单选和虚假直链提示 |
| tool/source_runtime/miomedia_adapter.py、test_miomedia.py | 已证实的纯文本解析拒绝分类及脱敏回归，不改供应商SDK |
| lib/services/source/sdk_playback_resume.dart、test/sdk_playback_resume_test.dart | seek确认前禁止瞬时0覆盖进度，确认后允许主动倒回片头 |
| lib/presentation/modern/library/sdk_library_widgets.dart | 共享新版卡片、管理及受限SDK导航 |
| lib/presentation/modern/library/modern_library_view.dart | 合并旧收藏与SDK收藏，保持状态/搜索/排序/布局 |
| lib/presentation/modern/home/modern_home_view.dart | 按真实时间合并继续观看，不改首页结构 |
| lib/pages/history/personal_history_query.dart | 合并身份命名空间、日期/来源/关键字筛选 |
| lib/pages/history/history_list_view.dart | 共用原分组/筛选样式，支持SDK行 |
| lib/pages/history/history_page.dart | SDK历史管理与清空边界，旧卡片继续原路径 |
| test/sdk_library_store_test.dart | 真实Hive持久化及隐私、独立删除和失败重试 |
| test/sdk_library_model_test.dart、tool/sdk_library_model_check.dart | 时间精度、JS整数语义回归 |
| test/personal_history_query_test.dart | 混排/命名空间/来源筛选 |
| test/sdk_manual_quality_test.dart | 保存的第99集/手动线路恢复，准备不更新历史 |
| test/sdk_playback_entry_test.dart | 新控制栏后等待真实滚动动画再点击，保留SDK选择断言 |
| docs/development/sdk-personal-library-plan.zh.md、source-sdk-onboarding.zh.md | 实施范围、契约及后续SDK接入门禁 |
| docs/analysis/sdk-interaction-audit-20261016.zh.md | 更新独立SDK持久能力现状 |
| openspec/changes/integrate-lumina-anime-prepared-playback/ | 个人库需求/任务/验收记录 |

回退：先停止播放并保存当前完整补丁与应用数据备份，仅撤回上述本轮实现；旧库不迁移所以仍按原流程可读。新增sdk_personal_library_v1可保留，不能通过卸载/清库/reset --hard回退。基线HEAD49970c0258ff360630f3e4f89af2f897b007e592早于整轮未提交SDK接入，不代表本轮单独回退点。
