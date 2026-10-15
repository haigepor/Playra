# 动漫来源能搜到但未匹配：定位与修复

日期：2026-10-15。范围：作品别名解析、自动搜索、页面目录会话与同作品校验；沿用现有新页面Token及紧凑布局。本次按M级相关模块修复执行，未创建OpenSpec变更。

## 实际复现

验收作品为Bangumi 975《航海王》（原名ONE PIECE）。实际SDK搜索结果：

| 来源 | 以“航海王”搜索 | 以“海贼王”搜索 |
|---|---|---|
| DM84 | 返回主条目“海贼王”，以及特别编辑版、电影等 | 返回“海贼王”主条目 |
| MXdm | 返回总集篇、特别编辑版、电影，缺少主条目 | 返回主条目 `/detail/1180/` |
| akianime | 返回主条目“海贼王”，以及其他版本 | 返回主条目 `/bgmdetail/IDDDDE.html` |

当前资料镜像的 `/p1/subjects/975` 返回 `name_cn=航海王`，没有结构化 `infobox`，但 `info` 中明确包含 `|别名={ [ワンピース] [海贼王] }`。这是来源自动匹配所需的身份证据，不应从“海贼王女”等相似标题推导。

## 根因与调用链

1. `BangumiItem.fromJson` 仅提取结构化infobox别名，漏掉镜像的Wiki info；详情已加载但alias仍为空。
2. `AnimeSourceSession` 固定引用进入页时的轻量对象。详情补全替换 `info.bangumiItem`，未同步目录会话；旧未匹配状态阻止再次准备。
3. 线路弹层和 `SourceCandidates.discover` 只搜索中文主标题。即使有别名，MXdm也不会用别名继续找主条目。
4. 目录缓存还可能保留手动查看的未匹配条目；会话按缓存数量标ready，存在误匹配风险。
5. 两端实际复测发现MXdm还有限频误判：站点明确要求搜索间隔3秒，适配层只等1秒；别名回退第二次查询得到HTTP200“系统提示/请不要频繁操作”页，SDK按空结果返回并缓存120秒。已调整MXdm搜索间隔，并把明确限频提示映射为RATE_LIMITED，禁止缓存成无作品。

修复后：资料解析 → `loadInfo/sourceSession.updateWork` 同步当前资料 → `searchMatches` 使用中文主名与资料确认的别名 → 精确同作品校验 → 去重真实作品引用 → 获取真实线路 → 弹层/自动选集共用结果。Web经同源HTTP运行时、Android经内置桥执行相同业务判断。

## 修复边界

- 兼容v0 `infobox.value`、p1 `infobox.values`、Wiki info明确别名字段；合并、去空格、去重，不从summary或其他字段猜名称。
- 搜索按中文名、中文别名、原名等顺序，规范化去重后最多4个关键词，总搜索取消预算25秒；首个提供精确匹配结果的查询即可停止。搜索错误保留重试状态。
- 保留原有精确名称契约，不截断季数、不按子串匹配；电影、特别编辑版、海贼王女不被当成主系列。相同引用去重，不同引用同名仍要求人工确认。
- 资料名称证据改变时取消旧目录探测、清除旧自动结论并重查；迟到响应不能回写。人工确认和正在使用的来源保持优先。
- 自动缓存按当前资料重新核对名称；手动查看的无关目录不能升格为自动候选。显式重试会刷新目录缓存。
- 不改变历史/收藏存储、自定义规则、真实剧集URL和线路ID；不为某部作品写死别名。

## 文件与回退

| 文件 | 改动 |
|---|---|
| `lib/modules/bangumi/bangumi_item.dart` | 兼容镜像Wiki别名及合并结构化别名 |
| `lib/services/source/source_candidates.dart` | 共用有界别名搜索、引用去重、自动缓存复核 |
| `lib/services/source/anime_source_session.dart` | 同步详情资料、重新匹配、人工确认和代次隔离 |
| `lib/services/source/content_search_playback.dart` | 资料入口预加载共用别名搜索 |
| `lib/presentation/modern/pages/modern_player_detail_page.dart` | 资料完成及打开线路时同步会话 |
| `test/bangumi_alias_matching_test.dart`、`test/anime_source_session_test.dart` | 真实数据形态、别名回退、误匹配、歧义、缓存/取消回归 |
| `tool/source_runtime/anifive_adapter.py`、`test_anifive_covers.py` | 遵守MXdm搜索3秒间隔，识别HTTP200限频页并阻止缓存 |
| 本文及统一SDK规范/验收模板 | 记录新SDK必须遵守的匹配契约 |

工作区原有172条变更，均保留。修改前快照在本机 `.dart_tool/source-matching-before-20261015/`；Bangumi模型快照为该目录 `bangumi_item.dart`，其他文件保留原相对目录。回退只恢复本次文件，不能整库还原。Git基准37501c88不是本次开始时的完整工作区状态。

## 验证记录

- DONE：先复现别名回退缺失、自动发现为空和无关缓存误标ready的3项业务失败；另复现Wiki别名缺失/合并的3项失败。
- DONE：当前核心匹配、会话和搜索预加载25项通过（补充合法NoResultException与网络失败的区别）；此前带日历/首页资料检查批次31项通过，批次重叠不累加。
- DONE：MXdm限频两项先失败（只等待0.99秒、未抛RATE_LIMITED），修复后Python来源/封面/Android桥/HTTP服务共47项通过。
- DONE：Dart分析无error/warning，剩余4项info级大括号风格提示。

## 最终收据

- DONE：最终完整Flutter套件671项通过，日志为本机 `.dart_tool/source-matching-before-20261015/flutter-final.log`；Python来源/封面/Android桥/HTTP服务47项通过。
- DONE：Web和Android x64 debug包重建通过，雷电 `adb install -r`覆盖安装成功，未清除数据。构建摘要在同目录 `build-hashes.json`。
- DONE：Web同作品弹层显示DM84两线、MXdm四线、akianime真实线路2和moonci；DM84→MXdm手动切线仍为第1180集，1920×1080、readyState4、1311帧、54秒以上，刷新首页保留第1180集1:07历史。
- DONE：雷电最新包同一《航海王》弹层显示DM84两线（1180集）、MXdm四线（1180/1181集）、akianime真实线路2（1180集）及moonci当前线（1113集）。原来的三个“未匹配作品”均已消除，截图为同目录 `android-final-lines.png`；Web对应 `web-four-sources.png`。
- DONE：雷电moonci→akianime真实线路2后仍为第1113集，实际画面及持续播放00:01→00:41/23:18已观察，证据为 `android-c-switch.png` / `android-final-progress.png` 及同名XML；保持手动状态。Web最终构建从首页第1180集1:07恢复，打开四源目录仍正确，MXdm当前使用标记正确。
- DONE：文本UTF-8无BOM/无替换字符，相关文件 `git diff --check`通过；未新增供应商凭证、签名地址日志或全局配置修改。

第三方接口可用性与“匹配到作品”分开记录，目录成功不代表所有媒体均可播放。此次DM84样例媒体失败仍保留换源和重试，不将它误记为匹配失败。更早Web控制台也含图片/弹幕等上游错误，未宣称所有第三方服务无错误。
