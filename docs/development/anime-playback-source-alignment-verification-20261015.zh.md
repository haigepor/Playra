# 动漫播放源分组与紧凑布局实施记录

日期：2026-10-15。对应[已确认方案](../analysis/anime-playback-sdk-source-alignment-20261015.zh.md)；接入约束以[统一 SDK 规范](source-sdk-onboarding.zh.md)为准。

## 目标与范围

本次为 L 级跨模块行为调整：动漫顶层按 AniFive 分组，下一层按 DM84 / MXdm / akianime / moonci 展示作品实际返回的线路；统一影视的来源面板、自动与手动语义，修复跨 SDK 切换首集。随后按用户提供的两张截图调整信息密度，避免重复的大卡片、站名和技术说明。

保留原 `providerId`、作品引用、剧集 URL、Bangumi 身份；未修改收藏存储、历史存储格式、自定义规则配置和媒体协议算法。工作区已有其他页面和图片的并行修改，本次只改播放来源相关组件，不覆盖这些更改。

## 修改文件与用途

| 文件 | 用途和影响 |
|---|---|
| `lib/services/source/source_sdk_group.dart` | 新增受管理 SDK 分组登记；未登记自定义规则独立成组；限定恢复范围 |
| `lib/services/source/anime_source_session.dart` | 页面级目录复用、单源错误/歧义状态、显式重试、取消与人工确认优先 |
| `lib/modules/roads/road_module.dart`、`lib/plugins/api_rule_config.dart`、`lib/services/plugin/api_rule_strategy.dart` | 新增可选 `Road.id` / `roadIdPath`；旧规则仍兼容 |
| `lib/services/source/source_candidates.dart`、`source_service.dart` | 筛除空目录时保留真实线路标识 |
| `tool/source_runtime/anifive_adapter.py`、四个 `assets/plugins/*.json` | 输出真实线路 ID 并映射 `$.id`；规则版本 3.1.0 |
| `lib/pages/video/video_controller.dart` | 自动恢复仅在当前 SDK；换线锁定手动；新地址就绪后提交；旧恢复不能抢占待提交选择；迟到选择作废；首帧后记录当前线路 |
| `lib/services/source/sdk_playback_coordinator.dart` | 接受经两侧单集电影证据确认的匹配，保留严格剧集匹配 |
| `lib/presentation/modern/pages/modern_player_detail_page.dart`、`sdk_player_detail_page.dart` | 接入公共面板/弹层，按当前集切源；无匹配时提示选集；保留旧媒体和经时长校验的进度 |
| `lib/presentation/modern/player/sdk_source_widgets.dart` | 公共紧凑来源栏、固定自动选项的线路弹层、分组线路按钮与影视选项行 |
| `lib/presentation/modern/player/player_theme.dart`、`test/playback_source_theme_test.dart` | 播放页继承新二级页面主题；检查字体、弹层、Chip选中态和浅色宿主隔离 |
| `lib/presentation/modern/player/player_episodes.dart` | 详情选集弹层可隐藏重复的线路下拉框；旧调用默认保留 |
| `lib/pages/video/playback_scaffold.dart`、`test/cold_history_resume_test.dart` | 冷启动先同步加载持久历史再按真实URL恢复，避免首页有历史但播放控制器空列表而跳首集 |
| `test/source_sdk_group_test.dart`、`anime_source_session_test.dart`、`sdk_source_switch_episode_test.dart`、`playback_source_panel_test.dart` | 新增范围隔离、目录缓存/取消、真实线路2、跨SDK同集/缺集、窄屏大字和固定自动选项回归 |
| `test/miomedia_sdk_ui_test.dart`、`content_provider_test.dart` | 未起播不标当前使用；修正已迁移为四源后仍断言16源的旧测试 |
| 本文、统一规范、分析文档 | 记录执行边界、证据、剩余风险与回退方式 |

## 行为回归证据

- 先复现跨 SDK 旧缺陷：当前第14集，目标第14集真实 ID 914，旧代码却播放首项 ID 912；目标无第14集时也误播912。修复后的两例通过。
- 分组、目录会话、真实线路、历史、迁移、API配置、媒体头、影视界面等专项批次92项通过；后补人工确认优先和紧凑弹层测试独立通过。批次有重叠，不相加作为独立总数。
- 全套首次运行644项通过、1项失败；失败是旧测试仍期望16条内置源，已按当前四源及其ID修正并单独通过。最终全套结果见下方交付收据。
- Python `test_anifive` / `test_anifive_covers` 共32项通过，线路 ID 为增量字段。
- 320px / 2倍字体检查公共来源栏和线路长列表，自动选项在列表滚动后保持原位。
- 重启后的历史复测发现独立缺陷：仓库为第2集344秒，但全局控制器尚未装载历史，严格URL恢复查空列表后误播第1集0秒。真实PlaybackScaffold测试先取得业务失败，再在初始化恢复时刷新仓库历史。

## 两端运行证据

Web 在独立本机端口18932运行，未干扰原18930页面。正式搜索结果进入《海贼王女》，顶层AniFive；实际取得DM84四条、MXdm四条、moonci一条，共9条，akianime目录本次请求失败并保留重试。手动MXdm线路1起播1080×608，随后超过30秒；显式恢复自动后仍为同作品第1集，续播到1分多钟，弹层同时显示自动选中与MXdm当前使用。

Android 使用雷电 index0 / emulator-5554，`adb install -r`覆盖安装保留数据。《航海王》moonci线路1实际画面、播放进度1:26、2:00已观察；手动换至第02话后持续播放，返回首页出现“航海王 第2集，看到5:44”。本机图片/XML放在忽略目录 `.dart_tool/source-alignment-before/`，不当作干净克隆自带文件。最终紧凑样式重建后的结果见交付收据。

## 信息布局约定

- 详情区：“播放源 + SDK标签 + 更多”同一行，下一行仅当前模式、站点/线路和数量；高级选源放入更多入口。
- 线路弹层：简短标题，自动模式固定在顶部，站点分组独立滚动；站名只写一次，线路采用紧凑按钮；集数在分组摘要显示，画质未声明不逐条重复。
- 无匹配、歧义、请求失败分别用短状态和确认/重试操作；不能为了简洁隐藏失败或自动误选作品。
- 保留48dp触控区域、选中语义、关闭名称、长名称换行、2倍字体和减少动效。
- 后续按用户截图再次收紧密度：未匹配/失败/加载态合并为“站点及状态 + 操作”的一行，去掉每站重复图标；内边距由16改为横12/纵8，组间距12改8。真实线路保留分组按钮，换行间距8改2；系统40dp拖拽区改为16dp主题色手柄，自动项纵内边距12改8。大字体按内容增高，不锁死行高；正常字体空状态目标约64dp。

### 新页面Token对齐

按后续用户要求，动漫与影视统一继承 `ModernPlayerScope → ModernSecondaryScope → ModernHomeScope + ModernSettingsScope`。来源组件直接消费已有 `modernHomeColors` 与 `modernSettingsTheme` 的语义Token：标题16/正文14/辅助12、Chip形状与选中色、卡片描边、弹层背景及20尺寸图标。移除组件内独立字体和选中色覆盖，影视线路弹层不再指定另一层背景和圆角。播放器Material画布也映射到同一卡片表面，避免半透明选中态叠在全局浅色画布上。未为播放页新增色板，也未修改全局主题定义；原主题的并行更改保留。

主题回归先取得失败（旧播放页标题22而新二级页为16），修复后通过。随后雷电截图发现Material2的Chip仍为浅底：Flutter此分支忽略 `chipTheme.color`，ChoiceChip另继承 `secondarySelectedColor`。已在 `ModernPlayerScope` 将同一新主题状态Token映射到Material2兼容字段，没有另建色值；测试覆盖Material2/3的实际Ink绘制颜色，先失败后通过。22项定向测试通过。首次Web编译另发现 `ShapeBorder` 不保证有 `copyWith`，已改为仅对 `OutlinedBorder` 更新描边，其他形状原样继承。最终构建及运行证据以下方收据为准。

## 回退与风险

本轮开始时的相关文件备份位于本机 `.dart_tool/source-alignment-before/`，保留了此前 SDK 接入更改。新文件可按上表单独移除；最初干净文件可对照基准 `37501c88`，不能整库回退以覆盖其他并行工作。后续样式只涉及上述公共组件和两类播放页。

第三方可用性仍有限：本次默认DM84媒体失败、部分akianime目录失败，图片CDN/弹幕服务出现502/403；未修改这些外部服务，也不声明四站所有作品和线路均可播放。Android验收使用当前雷电的软件解码/OpenGL设置，不代表所有真机解码器兼容。发布CI的私有AniFive输入恢复仍属既有独立事项。

## 最终交付收据

- DONE：完整 Flutter 套件在主题接入阶段649项通过；冷启动复现测试由第1集0秒转为正确第2集344秒。后续Material2/3绘制兼容及再次收紧间距后，主题/公共布局/影视界面/切源/冷恢复22项定向检查通过（主题测试扩为两种Material模式，不将重叠批次相加）。
- DONE：Python目录/封面专项32项通过；受影响文件UTF-8无BOM/无替换字符，`git diff --check`通过。Dart分析无error/warning，保留既有及局部info级风格提示。
- DONE：`flutter build web --no-pub --no-wasm-dry-run`、`flutter build apk --debug --no-pub --target-platform android-x64`通过；debug APK覆盖安装成功。Gradle/AGP/Kotlin存在将来版本支持提示，本次不升级构建链。
- DONE：最终紧凑版Web从首页第2集历史进入，MXdm实播1080×608、readyState4、1105帧以上，进度超过1分钟；仅一个video元素。自动/手动、真实多线路与异常入口在正式详情页检查。
- DONE：雷电最终布局第2集换集及冷启动恢复核对，持久历史0:40恢复后进度继续到1:11；此前同源第2集持续到5:44。保留历史、收藏和自定义规则数据；两端均未清库。
- DONE：公共来源栏压成两层，四站用紧凑线路按钮；短弹层按内容收缩，长列表独立滚动，自动选项固定。当前路线使用主题色与文字标识；2倍字体和320px检查通过。
- DONE：最新Token/间距版两端重建后核对。Web《海贼王女》第2集从14:22续播到15:12以上，1080×608、readyState4、1281帧；雷电保留其当时最新历史《航海王》第1113集18:17，恢复后继续到19:11。Android四站在同一屏完整展示：三个未匹配状态行和moonci真实线路；48dp操作范围保留，AniFive/当前线路深色选中态无浅底。
- DONE：文档规范与新增SDK检查模板同步，修改清单与回退位置见上文。

本机最终构建摘要见 `.dart_tool/source-alignment-before/build-hashes.json`，完整测试日志为同目录 `flutter-tokens-final.log`；更早分组/历史阶段日志为 `flutter-final.log`。这些是本机忽略的验收收据，不包含供应商算法或媒体凭证。

最新布局截图：同目录 `android-compact-final-lines.png`、`android-compact-final-detail.png`、`android-compact-final-progress.png`、`web-compact-final-lines.png`、`web-tokens-detail.png`。旧的 `*-prebridge.png` / `*-tokens-lines.png` 只记录中间状态，不用于最新版本验收。

NEXT（可选）：继续按作品/站点单独治理原站失败、补真机覆盖及私有SDK发布CI；不影响此次分组和布局验收结论。
