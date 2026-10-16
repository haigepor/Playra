# Lumina 三端接入与验收记录

日期：2026-10-16。变更：`integrate-lumina-anime-prepared-playback`。工作基线：`49970c0258ff360630f3e4f89af2f897b007e592`。代码未在本任务中提交或推送。

后续手动画质已完成：以[手动画质验收记录](sdk-manual-quality-20261016.zh.md)为最新构建与APK依据（744项回归通过、Web/雷电4K与1080p双向切换、暂停/进度/线路锁实际验证）。本文下方早一轮730项测试和安装包摘要属于当时的自动画质验收快照，不代表最新APK。

最新交付依据改为[SDK个人库与解析布局验收](sdk-personal-library-20261016.zh.md)：已追加统一历史/收藏/续播、Mio解析业务拒绝分类和紧凑详情布局。本文和手动画质报告的旧包摘要仅供历史追溯。

## 交付行为与平台边界

- 动漫优先Lumina频道、列表、搜索主资料与独立SDK详情；旧AniFive四源/自定义规则保留，影视继续MioMedia。支持平台共3套SDK/6个播放适配器；Android ARM32保留既有5个。
- 详情自动准备完整直链，点击前不打开媒体、不写观看历史；点击复用准备结果。换集/换线清除旧generation，过期重取，媒体403/410等在当前选择上限次刷新，不解除手动锁线。
- 原始视频ID为字符串，原始play/part不能改成位置编号；SDK特殊集可没有数字集号。旧历史、收藏、规则数据结构未迁移或重置。Lumina新作品不伪造Bangumi身份，本轮没有新增独立SDK收藏/追踪库。
- Web同源BFF接Python；Android仅arm64/x86_64内置SDK及只读JNI；ARM32不登记Lumina。按用户最新范围，iOS不登记/展示Lumina，保留旧动漫来源；即使配置影视远端地址，也不隐式启用Lumina。本轮暂停iOS本地及远端研究，原[可行性方案](../analysis/lumina-ios-local-feasibility-20261016.zh.md)仅为历史分析，未实施。
- 首页恢复原推荐Bento/Hero轮播/海报轨/继续观看和栏目结构，用真实SDK身份的展示模型供给数据；不再用独立Lumina品牌面板替换页面。保留原样式tokens，SDK未提供评分时显示暂无。
- 按用户确认，榜单名改为“热播推荐”，组合Lumina真实推荐序与Mio来源榜序，各条保留provider/contentId/sourcePosition，混排数字只是展示顺序，不宣称未经证实的七天统计。

## 固定接口契约

客户端POST `adapters/lumina/sdk`，仅允许 `{operation,payload}`，禁止额外host/脚本/模块参数。Web基址 `/api/runtime/v1/`；Python基址 `/v1/`；当前iOS不调用Lumina。

| operation | payload | 返回公开data |
|---|---|---|
| config | `{}` | available，不返回SDK配置 |
| channels | `{}` | channels：字符串id/name/types |
| banners | channelId | banners：id/videoId/title/cover |
| catalog | channelId/pageIndex/pageSize/sort | videos/pageInfo |
| search | keyword/pageIndex/pageSize | videos/pageInfo |
| detail | videoId | video/parts，保留真实play/part及分集标签 |
| play | videoId/playFormat/part | status/media/medias，包含原始headers |

稳定错误覆盖：INVALID_ARGUMENT、BUSY、TIMEOUT、CANCELLED、SDK_NOT_CONFIGURED、SDK_RESOURCE_MISSING、ENGINE_UNAVAILABLE、UPSTREAM_HTTP_ERROR、BUSINESS_REJECTED、DECRYPT_ERROR、PARSE_ERROR、RESOLVER_HTTP_ERROR、INVALID_MEDIA等；调用层按错误码显示可恢复状态，不公开原始信封/配置/堆栈。

SDK按worker线程复用Client和90秒认证缓存；设备指纹一次生成、私有持久复用。元数据缓存与准备结果分开：详情短缓存有界，显式刷新真实请求；直链仅页面内存保守30秒TTL，点击检查时效，禁止落库。`resolve=False`仍发起凭证网络请求，不能作为离线操作或完整准备成功标准。

## 已执行验证

| 项目 | 结果 / 证据 |
|---|---|
| 私有SDK算法完整性 | 导入19个文件；除允许的环境绑定外摘要一致；verify通过；原SDK目录不修改 |
| 原SDK自检与向量 | SELFTEST ALL PASS；VECTORS ALL PASS 11/11 |
| 原SDK离线门禁 | 6/6；未配置模式E2E SKIP符合双态设计 |
| 原SDK真连门禁 | 在忽略的验证副本注入部署配置与持久身份，check_all.py --net 7/7；E2E ALL PASS |
| Python宿主回归 | 122/122；包含真实HTTP路由、Host去重及真实banner的vname映射，不只测dispatch |
| Node Web宿主回归 | 38/38；包含真实上游传输保留空UA、Range/HLS/运行桥 |
| Flutter回归 | 加入Lumina4K/1080p、动漫备用分类和空状态后全量730/730；全量analyze退出0，无error/warning，改动文件聚焦analyze无问题 |
| Web构建 | Release成功；最新main.dart.js通过HTTP200读取且与构建文件SHA256一致 |
| Android打包 | Release成功；ZIP CRC、v2签名、arm64/x64库、镜像与模块完整性通过；ARM32/可选后端排除正确 |
| Android实际播放 | 雷电x86_64：Mio《唐探1900》解码3840×1608、PLAYING进度8666→21100ms；保留原航海王第68集10:24历史。Lumina4K补充见下节 |
| iOS构建/远端/真机 | **未执行/研究已暂停**：最新按用户要求不显示Lumina，保留既有来源；未触发GitHub构建 |

本轮本地证据保存在忽略目录 `.dart_tool/lumina-integration-20261016/`。仅对外记录公开结果与哈希；含供应商原始诊断的日志不提交、不上传公共附件。

### Web实际媒体证据

真实浏览路径：首页Lumina → 动漫搜索“海贼王” → Lumina详情。详情显示1180个真实part及“播放链接已准备，点击播放”；点击前DOM没有video。显式点击后播放器实测1024×576，paused=false，进度由25.746秒增至61.477秒，解码帧由622增至1478，随后暂停。截图：本地证据目录的`web-prepared.png`、`web-playing.png`。

媒体探测独立验证HTTP200、Content-Type video/mp4且前缀包含ftyp；另一轮Range得到206。只读取探测前缀并关闭连接，未下载整片。浏览器仍观察到旧Bangumi资料/图片代理的502及搜索某备用源失败，未宣称控制台零错误或所有来源可用；Lumina实际播放链已通过。

revision3 Web Mio《毒液：最后一舞》点击前准备完成且无video；显式播放实际1920×808，time16.724052→30.176948秒、frames409→732，随后暂停。《唐探1900》同轮Web取得206/video/mp4但未等到首帧，不标播放通过；同片安卓已实播，不能据此笼统判为SDK解析失败。

### Lumina 4K与最新构建补充

源码与SDK原值核验见[4K线路与画质分析](../analysis/lumina-quality-switching-20261016.zh.md)。第1集和最新集可能采用不同结构：沧元图/海贼王第1集只有未知画质mp4；沧元图第99集返回1080P与4K，Range元数据分别1920×888/3840×1776，不虚构黑边后的高度。

最新Web选择第99集自动准备2160p来源声明，点击前没有video；显式播放实际3840×1776，10.610598→20.147621秒、265→504帧、无媒体error，随后暂停。页面来源名为“动漫 · Lumina”，弹层为“自动（4K 优先）”。截图web-4k-prepared.png/web-4k-playing.png。

最新APK在雷电选择同一第99集，点击前已准备2160p、媒体session NONE/position0；显式点击后PLAYING，position14560→45560ms，页面实际解码3840×1776且“正在播放 第99集”，没有跳回第1集，随后经媒体键暂停。此为模拟器实播证据，不冒称实体手机验收。

最新Web release70.4秒，Android release80.1秒。APK为build/app/outputs/flutter-apk/app-release.apk，124597786字节，SHA256 `5921bd263da03f067eddfe8b10cb40d862929db2efff7dbdbd6f7bacf76c2bad`；完整性核验通过，雷电adb install -r成功，未清除数据。该设备没有monkey命令，改用系统am start启动，未修改业务代码规避环境差异。

### 本轮修复的问题

1. SDK小写host与宿主补Host重复，真实接入点返回HTTP400：改为不区分大小写去重并固定Host，补实线HTTP回归。
2. Python HTTP服务白名单漏了Lumina sdk路由：dispatch直接调用可用而Web返回404；修正固定白名单，真实HTTP测试先失败后通过。
3. Web `||=`覆盖SDK显式空User-Agent：改为仅缺省补值，保留Referer，实际transport测试验证。
4. 共享分集位置/数字身份不适合特殊part：新增opaque reference，保留Mio真实数字区间与旧URL身份。
5. 两类在线详情打开即播放：拆分准备/媒体打开，补点击复用、过期、取消、切源和旧历史回归。
6. 显式刷新Lumina详情仍读缓存：页面detail强制刷新，线路查找仍可复用缓存。
7. 首页Lumina慢请求阻塞Mio/备用内容刷新：独立发起后共同等待，补挂起Lumina时其他请求已发送回归。
8. Release构建残留开发插件注册类：`--no-pub`跳过release工具生成；改用正常`flutter build apk --release`重新生成，无需改依赖/业务或清空缓存。同一checkout的Flutter命令保持串行。
9. 轮播真实标题字段是`vname`，漏映射后显示SDK占位：新增字段归一与RED/GREEN回归，保留真实作品和图片。
10. 新SDK品牌网格改变原首页信息层级：改为原组件数据供给；首页推荐/分类与混合榜单携带真实详情回调，不制造Bangumi身份。
11. SDK徽标混排仍全动漫：电影SDK全站数据也以动漫为主，改读真实电影/剧集分类，不按SDK名字猜类型。
12. 上游真实空player仍显示正在获取线路：区分加载中、失败和无线路，禁止空目录继续提示选集准备；widget回归通过。
13. Lumina忽略quality且取medias首条：新增真实档位识别、4K→1080p偏好、单次解析材料消费及同线降档；旧单链仍未知。Mio动漫作为低优先备用，不抢专门动漫来源。

## 可复现命令

在项目根目录PowerShell激活 `. ./tool/use-dev-env.ps1`，随后按顺序执行Flutter命令：

```powershell
python -B -X utf8 tool/source_runtime/import_lumina.py --verify
python -B -X utf8 -m unittest discover -s tool/source_runtime -p 'test_*.py'
$webTests = @(Get-ChildItem tool/web_backend -Filter '*.test.cjs' | ForEach-Object FullName)
node --test $webTests
flutter analyze --no-fatal-infos
flutter test
flutter build web --release --no-pub --no-wasm-dry-run --output build/lumina-web
flutter build apk --release
adb devices -l
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

adb最后一条仅在设备已连接时执行；保留数据安装，不卸载/清空应用。真机需验证Lumina至少两部作品、真实part、解析失败恢复、显式点击播放、切集/手动锁线、旧历史收藏；当前这些真机项**未执行**。

原SDK真连门禁须在私有验证副本配置接入点和持久身份后执行`python check_all.py --net`，不得将原始日志或媒体URL复制到公开报告。不要改供应商算法。

## 历史远端配置方案（按最新范围暂停）

以下只保留已分析的宿主操作说明，不代表iOS当前启用了Lumina。iOS平台能力判断明确返回false，首页、搜索和榜单不登记Lumina；既有来源继续原路径。用户要求当前先完善Android/Web，本轮不再要求部署下述服务，也不实施iOS引擎/协议迁移。

服务端使用受支持平台的Python与随包_fuse，先私下恢复SDK输入、显式配置接入点，再执行完整性校验。服务代码已在`tool/source_runtime/server.py`，固定监听loopback：

```sh
python3 -B -X utf8 tool/source_runtime/import_lumina.py --verify
python3 -B -X utf8 tool/source_runtime/server.py --port 8945
```

由运维通过受控TLS网关映射到`http://127.0.0.1:8945/v1/`；例如管理员分配的`https://runtime.example/v1/`。`example`仅为待替换示例。运行目录及设备身份目录必须持久化且仅服务账号可读；每个worker线程独立Client，单引擎内部保持串行。依赖实际供应商私有输入，不能仅克隆公共仓库就认为已配置。

**访问控制前提**：当前X-Kazumi-Request只是请求标记，不是鉴权。现有客户端没有新增账号/token注入入口；先用受控VPN/网络ACL限制访问。若要面向公网多用户部署，应另行实现网关鉴权与客户端凭据契约；不能直接将此开发HTTP服务暴露公网。

Mac/Xcode上配置iOS远端入口后构建（本轮未执行）：

```sh
flutter build ios --release --no-codesign \
  --dart-define=PLAYRA_SOURCE_RUNTIME_URL=https://runtime.example/v1/
```

当前已有GitHub Actions同名Secret可为既有影视服务注入该编译参数，见[平台构建](../release/build-platforms.zh.md)，但当前iOS的Lumina登记已单独禁用，配置地址不会改变它。旧动漫来源不因此重置，不启动本地Python、不引入Unicorn。上述远端Lumina与iPhone播放均未执行。未签名.app/IPA不能直接安装普通iPhone。

## 推荐/热门必须混合内容类型

实时截图复核发现：仅交替Lumina/MioMedia来源仍会全部是动漫。真实Mio全站catalog首50条为国产动漫19、热门新番4、日本动漫27；全站hotRank前列也以动漫为主。因此通用推荐/热门需分别读取动漫、电影与剧集分类，不能只检查SDK徽标。

本轮真实接口验证：按search返回元数据发现电影大全和剧集大全，分别请求分类hotRank；电影返回《唐探1900》《毒液：最后一舞》，剧集返回《兰香如故》《无可替代》等。运行时不硬编码这次分类ID，也不以片名猜类型。主推荐以已成功加载的分类catalog与匹配kind/categoryId为证，榜单按对应分类读取，单类失败不清空其他有效类；晚到影视数据应进入推荐/热门主区，动漫分类页仍保持纯动漫。

## 影响与回退

修改覆盖运行宿主、受限路由、Android私有输入/JNI、共享SDK分集和准备状态、首页/搜索/详情及对应测试；统一规范与OpenSpec随实现更新。未修改旧Hive库、自定义规则文件或供应商算法；未改GitHub工作流、依赖版本、AGENTS/Skills/全局配置；未提交/推送。

回退基线为本报告开头SHA。应先保存本轮补丁，再在独立分支按文件回退宿主/平台/页面这一完整变更，避免只撤掉opaque分集模型的一半；不执行硬重置、不删除用户数据。私有vendor、运行identity和测试日志单独保留在忽略目录，不用公共Git传输。

性能依据见[优化分析](../analysis/lumina-sdk-optimization-20261016.zh.md)；iOS本地/GitHub构建能力见[iOS可行性核验](../analysis/lumina-ios-local-feasibility-20261016.zh.md)。

## 修改文件清单

以下为本轮工作树变更的文件级用途；影响及回退基线见上节。私有vendor本体、身份与构建日志不列为Git交付物。

| 文件 | 用途 |
|---|---|
| `.gitignore` | 排除私有Lumina构建输入，防止配置和算法意外公开 |
| `android/app/build.gradle` | 校验私有输入并打包只读JNI与运行镜像 |
| `android/app/src/main/kotlin/com/example/kazumi/SourceRuntimeBridge.kt` | 固定传递Android私有目录和原生库路径 |
| `docs/analysis/current-api-inventory-20261013.zh.md` | 接入规范、分析或验证记录与当前代码同步 |
| `docs/analysis/lumina-ios-local-feasibility-20261016.zh.md` | 接入规范、分析或验证记录与当前代码同步 |
| `docs/analysis/lumina-sdk-optimization-20261016.zh.md` | 接入规范、分析或验证记录与当前代码同步 |
| `docs/development/source-sdk-onboarding.zh.md` | 接入规范、分析或验证记录与当前代码同步 |
| `docs/release/build-inputs.zh.md` | 接入规范、分析或验证记录与当前代码同步 |
| `docs/verification/lumina-sdk-20261016.zh.md` | 接入规范、分析或验证记录与当前代码同步 |
| `lib/pages/info/info_module.dart` | 在线详情默认准备并保留原入口 |
| `lib/pages/video/playback_scaffold.dart` | 媒体打开等待用户意图，保留恢复循环 |
| `lib/pages/video/prepared_online_playback.dart` | 规则链准备结果及取消 |
| `lib/pages/video/video_controller.dart` | 接收已准备材料、隔离过期页面结果 |
| `lib/presentation/modern/home/home_anime_card.dart` | 原布局展示快照与独立SDK点击身份 |
| `lib/presentation/modern/home/modern_home_view.dart` | 复用原Bento/轮播/海报轨，渲染SDK与旧数据 |
| `lib/presentation/modern/miomedia/miomedia_browse.dart` | 通用海报支持共享SDK模型和短来源标记 |
| `lib/presentation/modern/miomedia/miomedia_home_controller.dart` | 记录成功catalog的真实分类ID，防旧页码/全站数据冒充影视 |
| `lib/presentation/modern/pages/content_search_screen.dart` | 独立动漫SDK进入真实SDK详情 |
| `lib/presentation/modern/pages/discover_page.dart` | 接线平台登记、内容和榜单随频道同步 |
| `lib/presentation/modern/pages/modern_player_detail_page.dart` | 旧动漫详情准备、点击与真实历史恢复 |
| `lib/presentation/modern/pages/sdk_player_detail_page.dart` | SDK详情准备状态、显式播放与同集切源 |
| `lib/presentation/modern/player/sdk_rank_section.dart` | 原横向海报布局渲染双SDK热播推荐 |
| `lib/services/platform/lumina_support.dart` | 统一平台能力入口 |
| `lib/services/platform/lumina_support_io.dart` | Android限制64位；iOS隐藏未验收Lumina |
| `lib/services/platform/lumina_support_stub.dart` | Web通过BFF提供能力 |
| `lib/services/source/content_providers.dart` | 登记可运行的Lumina提供方，保留旧规则 |
| `lib/services/source/content_search.dart` | 来源优先级稳定选择资料，不按返回先后猜身份 |
| `lib/services/source/lumina/lumina_content_provider.dart` | 动漫优先搜索及SDK来源声明 |
| `lib/services/source/lumina/lumina_home_controller.dart` | 真实频道分页、繁体分类与独立失败/预热状态 |
| `lib/services/source/lumina/lumina_models.dart` | 公开内容与真实分集模型 |
| `lib/services/source/lumina/lumina_playback_provider.dart` | 原始play/part播放、显式详情刷新 |
| `lib/services/source/lumina/lumina_service.dart` | 固定业务调用、详情有界缓存与刷新 |
| `lib/services/source/miomedia/miomedia_service.dart` | 共享nullable分集契约的兼容校验 |
| `lib/services/source/prepared_playback.dart` | 页面内短效准备缓存与generation所有权 |
| `lib/services/source/runtime/source_runtime.dart` | 固定Lumina操作路由与公开信封 |
| `lib/services/source/sdk_playback_coordinator.dart` | 共享准备/消费、身份校验与过期刷新 |
| `lib/services/source/sdk_playback_entry.dart` | 详情默认仅准备不自动播放 |
| `lib/services/source/sdk_playback_models.dart` | 扩展opaque分集reference，保留数字Mio兼容 |
| `lib/services/source/sdk_playback_provider.dart` | 完整分集对象的兼容播放接口 |
| `lib/services/source/sdk_rank_controller.dart` | 并行组合真实双SDK推荐，隔离失败/取消/身份 |
| `openspec/changes/integrate-lumina-anime-prepared-playback/.openspec.yaml` | 记录已确认范围、接口契约、验收和最新平台/UI约束 |
| `openspec/changes/integrate-lumina-anime-prepared-playback/design.md` | 记录已确认范围、接口契约、验收和最新平台/UI约束 |
| `openspec/changes/integrate-lumina-anime-prepared-playback/proposal.md` | 记录已确认范围、接口契约、验收和最新平台/UI约束 |
| `openspec/changes/integrate-lumina-anime-prepared-playback/specs/lumina-anime-content/spec.md` | 记录已确认范围、接口契约、验收和最新平台/UI约束 |
| `openspec/changes/integrate-lumina-anime-prepared-playback/specs/prepared-detail-playback/spec.md` | 记录已确认范围、接口契约、验收和最新平台/UI约束 |
| `openspec/changes/integrate-lumina-anime-prepared-playback/tasks.md` | 记录已确认范围、接口契约、验收和最新平台/UI约束 |
| `test/cold_history_resume_test.dart` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `test/home_content_mix_test.dart` | 真实内容类型混排、晚到分类与原布局兼容回归 |
| `test/lumina_content_test.dart` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `test/miomedia_content_test.dart` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `test/miomedia_player_style_test.dart` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `test/miomedia_sdk_ui_test.dart` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `test/sdk_playback_entry_test.dart` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `test/sdk_preparation_test.dart` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `test/sdk_rank_controller_test.dart` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `test/sdk_source_switch_episode_test.dart` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `test/source_runtime_test.dart` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `tool/source_runtime/adapters.py` | 可用宿主登记Lumina适配器 |
| `tool/source_runtime/android_bridge.py` | Android固定目录与平台资源绑定 |
| `tool/source_runtime/dispatch.py` | 受限固定sdk路由分发 |
| `tool/source_runtime/import_lumina.py` | 私有SDK导入与摘要校验，算法不修改 |
| `tool/source_runtime/lumina_adapter.py` | 受限SDK宿主、持久身份、有界传输及真实字段归一 |
| `tool/source_runtime/server.py` | Python HTTP白名单包含Lumina业务路由 |
| `tool/source_runtime/test_lumina.py` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `tool/source_runtime/test_server.py` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `tool/source_runtime/vendor/lumina-manifest.json` | 公开文件摘要/大小收据，不包含私有配置 |
| `tool/start-web.ps1` | 启动前校验Lumina私有输入完整性 |
| `tool/web_backend/lumina_media_headers.test.cjs` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `tool/web_backend/runtime.cjs` | Web BFF只允许固定Lumina SDK入口 |
| `tool/web_backend/runtime.test.cjs` | 对应行为与兼容性回归，验证真实边界及失败分支 |
| `tool/web_backend/server.cjs` | 媒体传输保留显式空User-Agent |
| `docs/analysis/lumina-quality-switching-20261016.zh.md` | 核对线路与画质层级、逐集双档、实际分辨率和手动入口边界 |
| `lib/services/source/source_display_names.dart` | 展示名称按动漫用途归类，Mio动漫标为备用，不改运行ID |
| `lib/services/source/source_sdk_group.dart` | AniFive展示名称同步新分类命名，保持管理规则与ID |
| `test/content_provider_test.dart` | 验证Mio动漫真实分类和低优先级后备 |
| `test/lumina_quality_preference_test.dart` | 双档4K优先、同线1080回退、旧链、失效重取及取消回归 |
| `test/source_display_names_test.dart` | 动漫主来源/影视动漫备用的命名契约 |
| `test/source_sdk_group_test.dart` | 分组显示改名后provider及自定义规则保持原值 |
| `test/sdk_detail_empty_state_test.dart` | 区分真实空目录、加载失败与等待，禁止空目录解析 |
