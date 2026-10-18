# Kazumi 自动主备来源调整

日期：2026-10-17。承接[原 16 条恢复](kazumi-rules-restoration-20261016.zh.md)和[真实 1080p 筛选](kazumi-1080p-lines-20261016.zh.md)，本次仅调整自动来源策略，未改规则资产、官方目录或解析协议。

## 生效规则

- 自动来源固定为 **akianime → mutefun → giriGiriLove**。前两者为默认优先来源，giriGiriLove 为备用。
- 其余 13 条受管规则继续显示在 Kazumi 手动列表，不进入自动选择和自动失败回退。手动操作不受名单或画质门槛限制。
- 使用受管规则的 `officialName` 和官方站点身份判断，用户改本地名称或 providerId 不会使优先级失效；自定义规则和其他 SDK 的策略保持原样。
- 缓存、历史成功率和请求响应速度不能让备用来源抢过尚未检查的主来源。禁用、冷却、无唯一同作品同集、目录失败或准备超时的来源跳过。
- 单来源搜索与目录准备最多 8 秒；每次自动播放最多尝试三个来源各一次，不再让同站多条线路或重复解析占完三个来源的预算。各站仍按官方目录顺序匹配同集，不猜测 SP 集号。
- 保留实际首帧尺寸门槛：实际解码高度至少 1080，未知或低清不自动接受；已知总长不足 10 秒的片段也拒绝。预解析成功、站点标签和来源白名单都不能替代实际播放判定。

本次不承诺整站所有作品持续达到 1080p，也不改变既有首帧判定为全程 ABR 清晰度锁定。

## 自动化验证

`flutter test --no-pub test/kazumi_automatic_sources_test.dart test/source_sdk_group_test.dart test/anime_source_session_test.dart test/video_startup_recovery_test.dart test/anime_playback_quality_test.dart test/kazumi_rules_test.dart test/modern_player_contract_test.dart`

结果：**56 项通过**。新增 9 项覆盖全 16 条保留手动且只有三条自动、主源顺序、已缓存备用不能抢先、两主源缺失后备用、其余规则仅手动、改名与禁用、8 秒准备上限、缓存回退顺序、取消后不启动备用；既有实测尺寸、未知尺寸、低清手动、短片段及播放器会话回归通过。

定向 `flutter analyze --no-pub --no-fatal-infos` 检查 6 个实现/测试文件：退出 0，无 error/warning，8 项 style info。

## 构建和页面验证

- `flutter build web --no-pub`：**通过，165.8 秒**。产物为正常 JavaScript Web 构建；既有 FFI Wasm dry run 不兼容提示仍在。
- Playwright MCP 打开 `http://127.0.0.1:18936/?kazumi=priority-20261017#/search/`，动漫搜索《葬送的芙莉莲》，进入第一季 → 详情与选集 → 播放线路。实际列表保留 7sefun、AGE、DM84、MXdm 等手动来源，自动选项显示新主备顺序和实际 1080p 门槛。
- 从手动 7sefun 切换“自动选择”，页面实际选择 **自动 · akianime / 播放线路1**，点击继续观看后起播。实际尺寸 **1920×1080**、时长 **1560.65712 秒**。
- 连续监测 **30.0015 秒**：进度 **12.999809 → 43.001389 秒**，视频帧数 **314 → 1033**，两端 readyState=4，0 waiting / 0 媒体 error / 0 dropped frames。截图已查看，确认实际番剧画面。
- 本次实播验证自动首选 akianime；主源失败后 mutefun → giriGiriLove 的顺序由专项测试证明，没有人为制造上游故障后宣称真实故障回退通过。mutefun/giri 的双集真实播放沿用前一轮记录。
- 控制台同时存在其他请求失败：隔离服务未启动 Lumina/Mio Python SDK（503），dalvdm（`www.sbdl.cc`）搜索和弹幕接口（`api.dandanplay.net`）403，最初手动 7sefun 预解析 502。这些没有计为三条自动来源实播失败，也没有标记修复。返回搜索页后确认 video 元素已清除；另出现一次未定位具体方法的平台 channel 异常栈，留作独立问题，不宣称页面控制台零错误。
- 测试标签已关闭，本轮 Node 服务停止；18936/18937 无监听。

脱敏证据：`.dart_tool/kazumi-priority-20261017/app-automatic-akianime.json` 和同名 `.png`；只保存尺寸、时间和帧数，没有签名媒体地址或请求凭据。9 个本轮文本文件严格 UTF-8、无 BOM/U+FFFD，`git diff --check` 和新增路径范围检查通过。

自动名单/优先级与 Web 实播：**PASS**。本轮没有生成 APK 或进行 Android 实播，不用 Web 结果替代原生端验收。

## 修改范围与回退

| 文件 | 目的和影响 |
|---|---|
| `lib/services/source/source_sdk_group.dart` | 定义受管 Kazumi 自动名单、主备顺序，保留全部手动分组 |
| `lib/services/source/source_candidates.dart` | 顺序准备、缓存排序、每来源超时和取消，其他 SDK 继续原调度 |
| `lib/pages/video/video_controller.dart` | 自动失败回退限名单并按来源分配三次预算，保留实际 1080p 判定 |
| `lib/presentation/modern/pages/modern_player_detail_page.dart` | 自动选线说明显示主备顺序与实际清晰度门槛 |
| `test/kazumi_automatic_sources_test.dart`、`test/video_startup_recovery_test.dart` | 新策略回归及将自动画质测试来源改为允许的 akianime |
| 开发接入文档、本记录及上一轮记录的后续链接 | 同步当前策略及验收边界 |

修改前副本：`.dart_tool/kazumi-priority-20261017/before/`，另保留工作区文件清单 `baseline-files.json`。回退只恢复本轮对应文件副本并移除本轮新增测试/记录；保留此前规则恢复、解析修复及其他原有改动。尚未提交或推送。
