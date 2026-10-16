# 首页加载与展示稳定性验收

## 范围与约定

按已确认方案实施。复杂度 L，依次完成复现、设计、实现、两端验证、差异审查。保留现有页面的颜色、尺寸、排版和内容导航，继续使用 Lumina 动漫优先、AniFive 备用动漫、MioMedia 影视的约定。

仅修改首页展示会话、目录请求调度、目录缓存、热播推荐和轮播定位及对应测试。不迁移或清理历史/收藏，不修改自定义规则、SDK 算法、设备指纹、播放解析、手动锁线或媒体请求。

## 展示契约

- 推荐四位置固定为动漫、电影、动漫、剧集。无影视服务的平台继续使用四个动漫位置。缺失来源只显示占位，晚到结果填自己的位置。
- 同一次浏览中，已显示条目的身份、内容和位置保持稳定。新增后台频道只追加候选，不能挤走正在看的卡片。
- 首屏优先等 Lumina，只有主源实际失败、超时或返回空目录后才采用备用资料；一旦采用备用，此次展示不被后续后台恢复覆盖。手动刷新或换批可采用已准备好的主源。Web/安卓实测发现短等待预算会过早选择备用，因此取消独立的四/八秒备用计时，使用现有 SDK 运行链路的真实超时、取消和错误状态；影视位置仍独立先显示。
- 页面继续提供原来的刷新、换批、分类、详情入口。刷新产生新的展示会话；换批只更新推荐批次。
- 热播推荐为固定来源位置的展示序号，不声称跨 SDK 的真实热度或七天统计。未返回的来源预留位置，不重新编号已有海报。
- 轮播数据补齐时保留当前作品；自动轮播仍为六秒，后台、离屏和用户操作暂停规则保持。

## 请求优化

- MioMedia 任一发现接口取得有效电影/剧集分类后即请求该目录，不再等待另一个发现接口。
- 首页资料补全与 Lumina 其他频道加载延后，先让主频道和影视首屏获得运行名额；四秒启动预算避免后台资料永远不开始。
- Lumina 目录缓存一分钟、最多十二项；首页第一页可为热播推荐提供同频道同排序的前十条。非第一页仅复用相同分页大小，避免偏移错误。
- 只有目录缓存，播放凭证、解析器和短效媒体地址不缓存。显式刷新失效缓存，取消和来源范围校验保留。

## 可重复验证

```powershell
. ./tool/use-dev-env.ps1
flutter test --no-pub test/home_loading_stability_test.dart
flutter test --no-pub --concurrency 2
flutter build web --no-wasm-dry-run
flutter build apk --release
```

专项覆盖：晚到电影/剧集填位，卡片坐标及区块高度不变；后台频道不能换掉当前推荐；主动换批有效；Lumina 超时备用及显式刷新；热播晚到主源不能移动已显示电影；搜索配置慢时分类目录仍提前开始；首页目录与热播推荐复用。

实现前上述四个核心复现均失败：动漫卡片从 `(518.4,135)` 移至 `(153.4,297)`；后台频道替换前四条；电影海报横移 156px；目录等待搜索配置。追加复现发现失败提示会将海报纵向挤动 64px，已把重试入口放在原标题行，不改变区块高度。

## 最终结果

| 验证 | 已执行结果 |
|---|---|
| 完整 Flutter 回归 | 761 项通过；之后真实超时策略与失败提示的最终补丁执行 57 项相关回归全部通过 |
| 静态与完整性 | 相关文件 analyze 无 error/warning，5 项花括号风格 info；UTF-8 严格解码、无替换字符、diff whitespace 检查通过；Lumina SDK INTEGRITY PASS |
| Web 正式构建 | 最终构建 101.7 秒，BFF `http://127.0.0.1:18972/`；1200×900 和 390×844 实页检查 |
| Web 异步数据 | 桌面与最终窄屏各次采样已显示卡片移动数均为 0；电影/剧集晚到或 Lumina 补齐自己的位置，不改已有海报序号；无文档横向溢出 |
| Web 请求复用 | 实际网络记录中主频道 `catalog(channel=1,size=24)` 一次，热播直接复用；其他频道随后独立加载 |
| Web 交互 | 换批确实更新内容；热门含动漫、电影、剧集；返回推荐恢复四个固定位置；沿用原色彩/卡片/间距 |
| Android 构建 | 最终 release 构建 114.6 秒，APK CRC 与 v2 签名通过，arm64/x86_64 Lumina 引擎仍随包 |
| Android 安装 | 雷电 x86_64，`127.0.0.1:5555`，仅 `install -r`、强停和启动，无卸载/清库 |
| Android 冷启动 | 4.109 秒采样为空位；11.266、17.562、23.875 秒采样为同四张卡、同坐标，移动数 0；动漫两位均来自 Lumina |
| Android 热播与换批 | 热播连续两次采样三张海报名称/边界完全相同；主动换批后为东京复仇者、唐探1900、无上神帝、逐玉，原位置尺寸保留 |
| Android 历史收藏 | 安装前后均 6 条历史；2 部收藏保留，沧元图第99集5:52、唐探1900 1:09仍可读；首页毒液0:21仍在 |

采样时间是取得语义树的时刻，不能冒充准确首次出画或单接口耗时。没有用这些不同冷启动样本宣称整体速度提升百分比。可量化收益为展示位移归零、去掉分类发现的额外等待，以及主频道目录重复请求从两次缩为一次。

保留边界：外部封面/资料请求仍有 404，未宣称零控制台错误；未实测实体手机或 iOS，Android 运行证据来自雷电。原规则迁移、自定义规则隔离、历史/收藏回归包含在完整测试中，未改写它们的存储代码或规则资产。

构建中遇到 `--no-pub` 保留旧 `GeneratedPluginRegistrant` 导致 release 引用已排除的 dev 插件 `flutter_native_splash`；最终使用正常 `flutter build web` / `flutter build apk --release` 重新生成平台文件后成功，没有修改 pubspec、Gradle 版本或 SDK 算法。

交付 APK：`build/releases/Playra-2.3.8-home-loading-20261016.apk`，124744662 字节，SHA256 `34a07f87fc5be9117ac8faf2c37bad896b7997b1dfd84d077bb384e8d3f2b831`。

脱敏证据：忽略目录 `.dart_tool/home-loading-fix-20261016/` 的 `web-final-trace.json`、`web-delivery-mobile-trace.json`、`web-delivery-{desktop,mobile}.png`、`full-tests-final.log`、`{web,apk}-build-delivery.log`；安卓 `android/delivery-cold-trace.json`、`delivery-rank-{a,b}.{json,png}`、`delivery-history.json`、`delivery-library.json`。第一轮 Android 旧包采样从四张资料卡全部变为 SDK 卡，也保留在 `baseline-home.json` / `baseline-late.json` 作为问题基线。

状态：复现、实施、针对性验证、Web/雷电验收、差异审查均 DONE；实体设备/iOS为未执行的可选 NEXT。

## 文件与回退

修改文件：`modern_home_view.dart`、`home_display_session.dart`、`modern_home_controller.dart`、`miomedia_home_controller.dart`、`discover_page.dart`、`sdk_rank_section.dart`、`modern_feature_carousel.dart`、`sdk_rank_controller.dart`、`lumina_home_controller.dart`、`lumina_service.dart`；新增测试 `home_loading_stability_test.dart`。

各文件作用分别为会话与预留位置、稳定池、刷新版本、影视提前加载及分类代际、首屏请求调度、热播占位、轮播保位、热播固定位置、可延后频道预载、短期目录复用。

本轮开始的工作树已包含前序未提交 SDK 接入。逐文件原始副本保存在忽略目录 `.dart_tool/home-loading-fix-20261016/baseline/`，原 Git 状态在同目录 `git-status-before.txt`。仅按本轮差异回退，不能将 HEAD 当成本轮起点整体重置，也不能卸载/清库回退。
