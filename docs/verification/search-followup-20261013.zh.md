# 搜索后续修正

基线 `e27b9046`。用户授权：修正输入 `tr` / 中文拼音时的重复文字；选中来源并行发起、不排队；进度不吸顶；搜索结果进入已有播放页；重建并刷新预览供用户验收。

范围：`content_search.dart`、`content_providers.dart`、`content_search_screen.dart`、对应测试、本记录。需要原始数据身份才能进入既有 `/info/` 路由，不伪造 Bangumi ID，不迁移历史/账号或修改私有 SDK。原有未跟踪分析文档和子模块变化保留。

输入诊断：保留了用户的英文重复和 `nninihnihanihao你好` 截图。逐键、快速键盘、模拟 composition 事件路径的表现不同；目前自动化没有稳定复现用户的全部重复过程，不能将猜测写成已确认根因。当前输入控件每次 controller 值变化重建整个 SearchBar；改为稳定 TextField + 独立清空按钮监听，保留原 token，并关闭自动纠正/智能标点。正常输入、IME composing、清空与移动光标需回归；真实输入法仍需用户在刷新后复测。

回退：逐文件还原至基线，或 revert 本轮提交；不 reset 工作区、子模块或用户数据。

范围补充：`lib/pages/info/source_search_entry.dart`、`info_module.dart`、`source_sheet.dart`、`modern_player_detail_page.dart`、`plugin_search_service.dart` 和对应测试。搜索使用只读 bundled 规则时，需将规则集合传给现有播放页和来源面板，避免新页面进入后失去来源；不写入用户安装列表。原动漫来源面板搜索也同时发起，目录验证仍独立处理。

`info_page.dart` 同步接收该来源集合，确保旧版呈现也遵循同一入口契约。

最新用户决定：取消资料确认弹窗；匹配成功后自动加载目录和首集，直接进入已有播放页。增加 `content_search_playback.dart` 的唯一资料匹配和首个有效目录准备；`source_search_entry.dart` 携带已准备播放上下文，SDK 搜索入口启动既有 MioDetailPage 的自动播放链路。匹配存在身份冲突时提示明确错误，不随机绑定其他作品。

## 实际链路

- 动漫：点击结果 → 复用真实 Bangumi 资料或自动唯一匹配 → 并行准备目录，复用已命中来源引用 → 首个有效目录返回 → 现有 `/info/` 播放页 → 自动解析首集或已核实的历史集数。详情、关联作品和剧集资料也在入场时自动加载，不等待播放按钮。
- SDK 影视/剧集：点击结果 → 现有 MioDetailPage → 自动加载详情、线路、剧集 → 自动请求首集播放。SDK 的来源验证和广告要求仍由现有实现处理。
- 无唯一身份、目录失败或媒体解析失败会保留明确错误和重试入口；不弹出资料选择窗口，不使用伪造身份。
- 默认全部选中来源立即发起；保留取消、单源超时和批次超时。搜索结果逐个显示，去重合并规则保持原有身份、年份和季号边界。

## 修改文件与影响

- `lib/presentation/modern/pages/content_search_screen.dart`：稳定输入控件、滚动进度、自动准备及现有路由入口。
- `lib/services/source/content_search.dart`：默认全部来源并发；`content_providers.dart`：保存原生资料供路由复用；`content_search_playback.dart`：唯一身份匹配与首个有效目录准备。
- `lib/pages/info/source_search_entry.dart`、`info_module.dart`：传递真实身份、已准备目录及来源集合；`info_page.dart`、`source_sheet.dart`、`modern_player_detail_page.dart`：现有新旧播放入口和切源共享来源集合。
- `lib/services/plugin/plugin_search_service.dart`：现有来源面板并发搜索；`lib/presentation/modern/miomedia/miomedia_detail_page.dart`：仅搜索入口开启自动首集加载，其余入口保留原行为。
- `test/content_provider_test.dart`、`content_search_screen_test.dart`、`content_search_session_test.dart`、`content_search_playback_test.dart`、`miomedia_content_test.dart`：原生资料、18 源同时启动、输入状态、滚动、目录先准备和 SDK 自动加载回归。

## 验证记录（2026-10-14）

- 针对性测试 32 项通过；全量 Flutter 回归 565 项通过。
- 相关搜索、路由、准备逻辑及测试的 Dart analyze 通过，无问题。SDK 详情文件原有的 brace 风格提示未纳入无问题结论。
- 新测试先发现单来源目录已就绪时被整体结束的空结果抢先覆盖；统一使用同一 Completer 完成成功/全部失败结果后通过。
- UTF-8、无 BOM/替换字符、LF 及 `git diff --check` 检查通过。测试生成的历史截图已恢复。
- 输入自动化验证不能替代用户实际中文输入法的复测；真实上游来源的在线状态也不等于本地回归测试通过。
- 实际 Web 发现另一处生命周期问题：父页面首帧回调可能早于主题本地化内的播放器挂载，`playbackKey.currentState` 为空导致启动调用被丢弃。改为直接向既有 PlaybackScaffold 传入准备上下文，由其挂载生命周期自动初始化；保留 URL 身份核实的历史续播。修正后播放器、目录和 SDK 针对性回归 19 项通过。
- 最终 Web 构建 71.9 秒、安卓 Debug 构建 33.1 秒通过；APK 已覆盖安装到 `emulator-5554` 并启动，保留原数据。
- Web 新版本逐键输入 `tr` 得到 `tr`；安卓实际 EditText 输入得到 `tr`。用户真实 IME 尚需复测。
- Web 搜索“吞噬星空”显示 18 个来源的增量进度；点击规则命中后直接进入已有播放页，目录 245 集、来源 7sefun、播放线路1、当前第01集自动就绪。无播放按钮点击、无资料确认弹窗，自动解析并实际播放；`video.readyState=4`、`paused=false`、`currentTime=21.609344`、时长 `1172.927982` 秒。截图：`.dart_tool/search-followup-final-autoplay-web.png`。
- 此次上游仍有 sbdl 搜索和弹幕接口 403；已与正常首集播放区分，不宣称所有来源在线。
- 相同 URL 的页面导航曾保留旧文档状态；增加临时刷新参数重新加载后验证了新 TextField 和播放行为。最终回到原搜索 URL，保留用户存储。
- 最后一次播放器挂载修正后的全量回归仍为 565 项通过。原搜索 URL 已重新加载新版本，输入为空并停留在搜索页；安卓最终 APK 已再次覆盖安装并进入搜索页。

结论：本轮功能修改及 Web 自动首集播放验证通过；真实中文输入法复测与各来源即时可用性仍由实际环境决定。回退到基线 `e27b9046` 的本轮文件即可恢复前行为，用户存储不受本轮改动迁移。
