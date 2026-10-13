# 四频道与增量搜索实施记录

基线：`24e04806`。分支：`codex/content-search-20261013`。

实施契约为 `docs/analysis/content-categories-search-plan-20261013.zh.md`。目标：四频道登记、有限并发与增量展示、来源内去重和作品聚合、独立目录验证、保留来源与平台兼容。暂不迁移账号/历史/下载或修改私有 SDK。

允许修改范围：`lib/services/source/content_*`、`lib/services/source/source_profile.dart`、`lib/services/source/source_models.dart`、`lib/services/source/source_candidates.dart`、`lib/services/plugin/plugin_search_service.dart`、`lib/pages/info/source_sheet.dart`、`lib/pages/info/source_sheet_view.dart`、`lib/pages/search/search_module.dart`、`lib/presentation/modern/pages/content_*`、`lib/presentation/modern/pages/discover_page.dart`、`lib/presentation/modern/home/modern_home_controller.dart`、`lib/presentation/modern/home/modern_home_view.dart`、`lib/presentation/modern/miomedia/miomedia_*`、对应测试及本记录。其他文件如确有必要，先在记录中说明。

初始已有两份分析文档为未跟踪文件，子模块 `fastlane/.libmpv-android-video-build` 有本机变化；不回退、不纳入本轮代码提交。

范围补充：`source_policy.dart` 需在用户覆盖旧 domains 时保留 contentGroups；`miomedia_rank_view.dart` 需处理新增影视频道的穷尽 switch，不虚造合并榜单。剧集地区筛选在公共 Query/Session 实现，合拍地区保留多值。

验收：快源先发布、慢目录不阻塞搜索；旧查询取消；同源重复消除、同作品保留多源、异季/异年/异类不误合并；重复页不错误结束分页；空频道无请求；目录成功不冒充起播成功。Web/Android 共用 Dart 契约。

回退：本轮提交可逐项 revert；不重置工作区、子模块、用户数据或旧分析文件。

## 最终行为

- 顶级频道统一为动漫、影视、漫剧、剧集。影视含电影/综艺/纪录片；剧集含全部真人连续剧和短剧，国产/港台/日韩/欧美等按地区筛选。
- 动漫登记现有 16 条内置规则；MioMedia SDK Adapter 支持影视、漫剧、剧集，保留它已经实现的跨类别内容。新来源通过同一 Provider 契约登记；没有实现的占位不发请求、不冒充在线。
- 首次规则列表为空时，只读加载 bundled 规则，不安装、不覆盖用户列表。已有规则列表和禁用状态优先。
- 搜索默认全局并发 4、同 origin 并发 2、单请求 20 秒、整批 35 秒。每个来源返回就更新作品列表；目录验证另用并发 2 的队列，不占搜索槽位。
- 来源内以 providerId/contentId 去重；跨来源只有身份 ID 或片名/类型/年份等充分证据才聚合。无年份的同名条目保持独立，在作品页作为同名候选列出，选线路前需要人工确认。异季、异年、异类和已知身份冲突不会合并。
- 翻页保留各来源页码。重复页、地区过滤后空页都不直接判定结束；旧查询、旧线路和离页后的迟到结果被丢弃。
- 搜索、目录验证均不提前解析媒体。点击剧集才 resolve；“线路可选 · 未试播”与“已起播”分开。剧集超时显示 TIMEOUT 和重试指引，不显示为无剧集。
- 打开 Bangumi 原资料入口前取消解析、等待媒体串行操作并暂停；转移过程中禁止新选线/起播，避免隐藏页面迟到播放。

## 样式修正

按用户后续截图反馈，搜索页和作品页接入既有 `ModernSecondaryScope`，复用 `modernHomeColors`、`modernSettingsTheme`、`SecondaryTabs`、`SecondaryEmptyState`、`ModernBackButton`。没有新增色板或改全局主题。

搜索框使用现用 SearchBar 的 48dp 高度、12px 圆角和 card/outline/mutedForeground token；频道使用短线 Tab；地区使用紧凑菜单；状态区与结果卡用既有表面色，移除白色默认 Chip 和贯穿页面的默认分隔线。320px 下只缩小本页 Tab 内边距，保留完整标签和 48dp 触摸高度。

## 接入下一条接口的约定

1. 在 `content_providers.dart` 或同级模块实现 `ContentSearchProvider`，明确稳定 id、name、origin、groups 与 canPlay。
2. search 只返回标准 ContentHit、上游分页 hasMore；明确分类、真实年份/版本/资料 ID，保留原来源引用，不从标题猜类型，不把用户查询写成可信别名。
3. lines/episodes 只取得目录；resolve 在用户点击播放时取得 URL 和必需 headers，并传递取消信号与标准 SourceException 错误码。
4. 在 registry 显式登记实例。规则类来源用 `sourceConfig.contentGroups` 声明 `anime/screen/comicDrama/series`；既有 domains 继续服务原兼容逻辑。
5. 至少覆盖快慢源、部分失败、取消、身份冲突、重复页和目录超时。接口未知时仅留扩展点，不增加伪请求实现。

## 修改文件与影响

| 文件/范围 | 用途与影响 |
| --- | --- |
| `lib/services/source/content_search.dart` | 统一查询、作品/来源身份、匹配与增量调度 |
| `lib/services/source/content_providers.dart` | 规则、SDK、Bangumi Adapter 与只读首次 registry |
| `lib/services/source/content_source_controller.dart` | 独立目录池、延迟剧集、取消/超时状态 |
| `source_profile.dart` / `source_policy.dart` | 新 contentGroups，保留旧领域和本地设置 |
| `plugin_search_service.dart` / `source_candidates.dart` / `source_sheet.dart` | 旧动漫找源增量发布；目录不阻塞；用户输入不成为可信别名 |
| `content_search_screen.dart` / `content_work_page.dart` | 共用搜索、独立候选确认、真实来源播放和 token 样式 |
| `search_module.dart` / `discover_page.dart` | 搜索路由和首页入口；原高级资料搜索仍可到达 |
| `modern_home_controller.dart` / `modern_home_view.dart` | 四顶级频道与既有动漫子筛选 |
| `miomedia_home_controller.dart` / `miomedia_browse.dart` / `miomedia_rank_view.dart` | 影视频道兼容、重复页继续翻页 |
| `test/content_*_test.dart` / `plugin_search_incremental_test.dart` / `modern_home_view_test.dart` | 关键边界与四频道契约回归 |
| 本记录与 `content-search-*.png` | 验收说明和实际界面截图 |

## 验证

- 全量 `flutter test --no-pub --reporter expanded`：558 项通过；随后最后的 Tab 内边距修正再跑搜索页 5 项，均通过，并增加标签实际宽度不裁切的断言。
- `flutter analyze --no-pub --no-fatal-infos`：退出码 0，无 error/warning；37 条既有 info。改动核心文件的独立 dart analyze 无问题。
- 已对“同名稀疏证据误合并”和“延迟线路超时误显示为空目录”先复现失败，再验证修复；手动候选确认有 Widget 交互测试。
- Standards/Spec 两轴审查完成：上述两项和资料导航生命周期问题已修复。地区正则误读已撤回，JP US / JP+制表符+KR 测试通过。
- Web 最终预览入口 `lib/main_home_preview.dart` 构建通过，使用同一业务路由/契约与实际代理。检查 1280px、390px、320px、地区菜单、搜索、选源、选线、返回和空状态。
- Web 搜索“火影忍者”：实际调度 17 个任务（16 规则 + Bangumi），在尚有任务运行时已有结果；最终保留 71 个条目，6 个来源需重试。证据不足的同名条目按规范独立保留，不能将这个数字当成 71 部不同作品。
- Web 国产剧搜索“庆余年”：实际返回 7 条，原作与第二/第三季分开；原作取得 MioMedia 高速线路和 44 集目录。没有点击剧集 resolve，未声称实际起播。
- 安卓 debug APK 构建并安装成功；使用 `am start` 打开实际应用（设备没有 monkey 命令，已使用等效入口）。四频道首页、新搜索页、原生输入 Naruto 后的 30 条结果已检查。设备采用其已有启用来源列表，不覆盖为内置 16 条。
- 实际外部来源可能失败或超时。浏览器曾出现封面代理失败；安卓原有版本检查返回 404，未发现本轮导致的 Flutter 布局异常。Android 构建有既有 Kotlin/Java 版本及 Python bytecode 提示，不影响成功生成 APK。

最终预览为 http://127.0.0.1:9006/ 。仅启动本轮独立 Node/Python 验收服务，保留原有 8945 等服务。

最终 APK：`build/app/outputs/flutter-apk/app-debug.apk`。SHA-256：`322BF68B2AEBF65E0129A03F285D524CD1BA4559892D0CEBA08F6B2C10B59C94`。最后的 320px 样式修正已重建 Web/Android，并重新安装成功。Windows UTF-8 无 BOM、替换字符与 LF 检查覆盖本轮文本文件，`git diff --check` 通过。

## 剩余边界

目前规则搜索普遍缺少年份/版本字段，同名条目需要手动核对。正式全自动换源需要更充分身份与剧集映射证据。所有 16 条来源今天在线、所有端点可用、SDK 奖励条件下解析和真实首帧均不在本次已验证结论内。

未迁移账号、历史或下载；未修改私有 SDK、全局配置或子模块。新增独立来源未来按上述契约接入。提交保留在本地分支，未推送或合并。
