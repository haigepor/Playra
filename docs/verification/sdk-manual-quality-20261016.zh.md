# SDK 手动画质切换验收

日期：2026-10-16。配套[交互核验与能力缺口](../analysis/sdk-interaction-audit-20261016.zh.md)、[统一接入规范v1.7](../development/source-sdk-onboarding.zh.md)。本报告仅记录本轮手动画质；此前完整接入见[Lumina接入验收](lumina-sdk-20261016.zh.md)。

后续统一历史/收藏、解析错误和紧凑详情已实施，最新安装包和验证见[SDK个人库与解析布局验收](sdk-personal-library-20261016.zh.md)。下文旧包摘要不代表最新交付。

## 行为与检查

- Lumina默认自动4K优先，缺4K自动选1080p；手动明确选档仅尝试该档位，不暗中降档。
- 线路与画质锁独立：手动选线后切1080p/4K或恢复自动画质，不解除线路锁；换集保留偏好，换SDK清除旧SDK私有画质码。
- 进入详情只准备；点击前换画质也只准备。播放中切换绑定同一part，在提交前读取最新进度，按真实时长恢复；暂停切换保持暂停。
- 档位来自当前集真实元数据。旧单链不出现假4K按钮；来源声明和实际解码宽高分开。控件复用ModernPlayerScope的新版主题、ChoiceChip及48dp触控规则。
- 原历史、收藏和自定义规则不重置；新SDK独立持久收藏/历史尚未统一，本轮没有伪造Bangumi身份。

## 已执行自动检查

| 检查 | 结果 |
|---|---|
| 重点SDK/准备/手动锁线/暂停/进度回归 | 42项通过 |
| 完整Flutter回归 | 744/744通过，包含待播第99集窗口回归 |
| 全量静态分析 | 退出0，无error/warning，50项info；未将info当作错误隐藏 |
| 最终改动范围静态分析 | 无error/warning，5项单行if花括号风格info |
| 源码编码与diff | 严格UTF-8无BOM/替换字符，diff --check通过 |
| OpenSpec | 严格校验通过 |
| 真实双档媒体元数据 | 沧元图第99集：1080p为1920×888，4K为3840×1776；均H265/MP4/HTTP206 |

## 两端实际验收

最终Web构建完成（66.7秒）；最终Android release构建完成（Gradle 95.1秒）。在同一《沧元图》第99集、手动锁定线路3上实际执行以下交互，未切换作品或清理用户数据。

| 场景 | Web浏览器 | Android雷电，127.0.0.1:5555 |
|---|---|---|
| 详情及选第99集 | 自动准备；点击前DOM无VIDEO；选集窗口显示96–99 | MediaSession为NONE、位置0，未自动播放；真实分集目录99项 |
| 点击播放 | 实际3840×1776、解码帧递增、时间推进 | 实际3840×1776出画；PLAYING，18.400秒 |
| 播放中选择1080p | 实际1920×888，时间继续推进；仍第99集、手动线路3 | 实际1920×888，PLAYING，从切换时约26.400秒续播到38.640秒 |
| 暂停后切回4K | 暂停39.381048秒 → 4K暂停39.381秒 | 暂停46.200秒 → 4K仍PAUSED、46.200秒 |
| 恢复自动画质 | 仍4K、暂停39.381秒、手动线路3 | 仍4K、PAUSED、46.200秒、手动线路3；当前集第99集 |
| 原数据保留 | 不改存储模型 | 覆盖安装成功；首页原《航海王》第68集10:24仍在 |

实际解码宽高对应裁边视频，不把3840×1776写成实际3840×2160。切换过程媒体重新打开时可能瞬时显示0，最终恢复状态才作为验收依据。两端已查看真实画面截图；安卓最终停在暂停状态。

补充能力核对：MioMedia《毒液：最后一舞》当前返回1080p，页面仅显示自动/1080p；点击1080p仍只准备，不自动播放。AniFive未提供可确认档位，不显示虚假4K选项。自动缺4K回退1080p、手动缺档报错及迟到结果隔离通过回归测试验证；没有把这些测试说成所有作品均已实播。

Web控制台仍有封面/Bangumi代理404/502等既有错误，未宣称零控制台错误；本次所播video.error为空。安卓已检查稳定错误码，未发现解析/媒体/引擎错误；实体手机、iOS、ARM32 Lumina及全部来源逐站实播均未执行。后两平台按约定不登记Lumina。

当前SDK原始play请求仍仅videoId/playFormat/part，qualityCode只在Flutter接入层选链，不改供应商协议。已执行Web真实操作及ADB取证的脱敏材料保留在本机忽略目录`.dart_tool/lumina-integration-20261016/`，包括`web-manual-quality-final.png`、`android/final-1080-playing.json`、`android/final-4k-paused.json`、`android/final-auto-settled.{json,png}`及完整测试日志；不保存私有请求头或直链到本报告。

## 最新安装包

- 路径：`build/app/outputs/flutter-apk/app-release.apk`，版本2.3.8+20308。
- 大小：124642942字节（约118.9MiB）。
- SHA-256：`1b8fb093de8d8fde65f612351d658304cf59bf442ac2d435c40f2e8665dbc6e9`。
- ZIP CRC、SDK模块/镜像/原生可加载段摘要及v2签名校验通过；ARM32不含Lumina引擎，未打入可选仿真后端。
- 使用`adb -s 127.0.0.1:5555 install -r build/app/outputs/flutter-apk/app-release.apk`覆盖安装成功，没有卸载或清库。

## 本轮文件级变更

| 文件 | 目的与影响 |
|---|---|
| lib/services/source/sdk_playback_coordinator.dart | 精确档位筛选、与线路锁独立、画质超时结束等待 |
| lib/services/source/sdk_playback_models.dart | 画质状态与4K可读标签 |
| lib/services/source/sdk_playback_provider.dart | SDK声明自己的自动画质文案，避免页面猜具体协议 |
| lib/services/source/lumina/lumina_playback_provider.dart | Lumina自动策略名称；真实档位协议保持原样 |
| lib/services/source/sdk_playback_resume.dart | 时长容差与越界进度校验，可独立回归 |
| lib/services/player/source_media_player.dart | 本次媒体打开可保留暂停，不改变全局设置 |
| lib/presentation/modern/pages/sdk_player_detail_page.dart | 手动选档、两类锁、提交前采集进度、取消与错误交互 |
| lib/presentation/modern/player/sdk_quality_selector.dart | 新版主题下的紧凑真实档位控件 |
| test/sdk_manual_quality_test.dart | 同集、线路锁、缺档、快速切换、大字布局 |
| test/sdk_playback_resume_test.dart | 毫秒进度、相容时长、不同版本与越界 |
| test/sdk_playback_coordinator_test.dart | 明确档位不升降/换线，超时不保留loading |
| test/source_media_player_test.dart | 暂停打开不修改原生全局播放配置 |
| test/miomedia_sdk_ui_test.dart | 自动线路/自动画质独立后的共享UI契约 |
| test/miomedia_player_style_test.dart | 大字模式按真实滚动操作进入选集，保留倒序真实ID验证 |
| docs/analysis/sdk-interaction-audit-20261016.zh.md | 三SDK现状、修复项、历史收藏缺口与未实施边界 |
| docs/analysis/lumina-quality-switching-20261016.zh.md | 更新当前手动档位能力 |
| docs/development/source-sdk-onboarding.zh.md | v1.7约定画质/线路独立状态与SDK精确选档 |
| docs/verification/sdk-manual-quality-20261016.zh.md | 本轮可复现证据与范围 |
| openspec/changes/integrate-lumina-anime-prepared-playback/tasks.md | 追加本轮实施与验收任务 |
| openspec/changes/integrate-lumina-anime-prepared-playback/specs/prepared-detail-playback/spec.md | 固定手动选档、保留进度/暂停及取消契约 |

Git工作树中此前Lumina接入改动继续保留，未提交或推送。本轮没有改SDK算法、Python参数、媒体代理、Hive库或规则资产。回退参考HEAD49970c0258ff360630f3e4f89af2f897b007e592及完整接入报告，但该SHA早于整轮未提交接入，不能对脏工作树直接硬重置；须先保存当前补丁，再在独立分支按上述手动画质范围撤回，不清用户数据。
