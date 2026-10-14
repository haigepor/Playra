# SDK 播放源、动态线路与画质选择实施记录

日期：2026-10-14。实施基线 `a8fddbcb738bd3964a48262315529969f241bb38`。需求以同目录的 `sdk-provider-lines-quality-plan-20261014.zh.md` 为准。

## 已实现的契约

- 播放源为 SDK，当前名称固定展示 `miomedia`；播放线路使用当前作品详情的全部合法线路，不把曾观察到的 7 种代码写成白名单。
- `ContentSearchProvider.sdkPlayback` 为可选能力，统一入口保存 `providerId + contentId`。同一 SDK 有多个歧义作品身份时不随意取第一条。
- `SdkPlaybackProvider` 封装详情、目录、画质和解析；`SdkDetailPage` 与协调器只认通用模型。旧 Mio 页面入口保留兼容包装；Android 继续复用原生 PlayerController/PlayerItem，Web 继续使用 media_kit/ArtPlayer。
- 目录与清晰度最多 3 路并发，元数据整体预算 10 秒；当前选集匹配成功后立即保留目录，清晰度超时仍可重试。首次加载直接并发，避免首条慢线路挡住其他线路。
- 自动模式先按有证据的清晰度降序，再按本平台成功与耗时排序；同档其他线路优先于降档。播放换取和实际播放器串行，整体预算 75 秒，同时约束解析和媒体打开。
- 手动换线会匹配同一剧集的真实编号并直接播放，保持手动模式。特殊集名完整匹配；普通集名可按集数匹配；单集电影只有电影元数据与双侧单条目录同时成立才允许跨名称匹配。
- 取消与选择代次防止旧请求覆盖新的来源、线路或集数；媒体打开串行，超时的迟到媒体停止播放。新地址准备期间尽量保留旧媒体。
- 只有新旧时长差不超过旧时长的 2% 加 2 秒、且目标进度小于新时长时续播；否则从头播放并解释版本时长差异。这是兼容判断，不能保证不同剪辑逐帧对齐。

## 画质的证据与限制

SDK `qualities` 和解析返回的 `height/resolution/1080p` 等可用于比较。“蓝光超清+”“原画”等名称不能自行换算成 4K。

Python 桥保留原始解析响应独立的高度/尺寸字段，按地址关联到 SDK 标准化后的媒体；未指定画质时使用最高已知候选。请求的 SDK 档位与解析命名不一致时，保留合法视频与实际画质证据，不能把“高清/超清”或字符串 URL 数组误判为解析失败。身份、签名、算法、TOKEN 策略与一次性换取逻辑保持原 SDK 行为。

播放器实际解码后显示完整尺寸，例如 `1920×800 · 实际分辨率`。宽银幕裁掉黑边后高度可能是 800，不能据此把片源简单说成低清“800p”；另一份 1920×1080 可能包含黑边。两个样本的画面内容、码率及剪辑是否相同，不能仅凭尺寸证明。

自动策略是已取得证据下的优选。当前真实样本的 SDK 声明常为 1080p，因此无法承诺预先确定每条线路的实际码率或绝对最高观感；不会为了比较而同时兑换所有线路、启动多个播放器。

## 界面与动效

沿用现有深色、淡紫色 token。SDK 选择和线路入口分层；线路面板使用卡片、SVG 图标及轻装饰，关闭按钮使用可见的主题前景色。自动模式只显示一个选择勾，当前线路另用“当前使用”说明；选中状态同时提供给读屏。

弹层进退约 260/200 毫秒，选项淡入和位移约 220 毫秒，线路文案柔和切换。全部遵守系统减少动态效果设置，没有循环装饰动画。SVG 由代码绘制，颜色由主题着色，不需要网络图片。

## 修改范围与回退

| 文件组 | 用途与影响 |
|---|---|
| `lib/services/source/sdk_playback_{models,provider,entry,coordinator}.dart` | SDK 通用契约、身份入口、并发比较与播放会话 |
| `lib/services/source/miomedia/miomedia_{service,playback_provider,playback_coordinator}.dart` | Mio 适配与旧接口兼容 |
| `lib/services/source/content_{search,providers}.dart` | 来源注册增加可选 SDK 播放能力 |
| `lib/presentation/modern/pages/{sdk_player_detail_page,content_search_screen}.dart` | 通用播放页与搜索跳转 |
| `lib/presentation/modern/miomedia/miomedia_detail_page.dart`、`lib/pages/info/info_module.dart` | 首页及历史入口兼容、自动起播 |
| `lib/presentation/modern/player/sdk_source_widgets.dart`、`assets/images/sdk-*.svg` | 线路卡片、SVG 和减少动效适配 |
| `tool/source_runtime/miomedia_{adapter,quality}.py`、`android/app/build.gradle` | 画质选择及 Android 随包 Python 模块 |
| 新增 3 个 SDK Flutter 测试文件与 `test_miomedia_quality.py` | 并发、画质、失败降级、手动锁定、第二 SDK 及界面回归 |

无持久数据迁移；回退到上述基线中的对应旧实现可恢复原播放链路。实际交付以本记录末尾的验证及安装包收据为准。预先已有的分析文档、`recipes.json` 与播放器子模块修改未纳入本次实现。

## 验证记录

- 最终全量 Flutter：605 项通过；Python：57 项通过；ArtPlayer 桥：6 项通过。分析使用仓库 CI 同款 `--no-fatal-infos`，0 error / 0 warning，保留 41 项 info 提示。
- 第二个测试 SDK 使用不同作品 ID/线路编码，通过相同页面切换与解析；产品未显示虚构接入项。
- Web 真电影《F1：狂飙飞车》自动起播成功：1920×800、播放时间持续增长；手动切换备用线路1后解码 1920×1080，并接续进度；始终只有一个 video 元素。
- 界面追加验证覆盖 320 像素宽、2 倍文字、9 条动态线路、单一选择标记、读屏选择状态及系统减少动态效果。
- iOS 本轮没有真机验证；共享新页面不等于 iOS 影视运行服务已部署或实际播放通过。

最终 Web release 构建已同步到本机 9006 预览服务，构建目录与服务目录的 `main.dart.js` SHA256 一致。Android release 构建成功；安装包仍沿用本地测试签名，不代表商店发布。自动化与 Web 实播证据不能替代最新 APK 的完整真机逐线路验证。

后续新增来源统一遵循[接入规范](../development/source-sdk-onboarding.zh.md)，复制[验收模板](../development/templates/source-sdk-checklist.zh.md)。README 与旧 SDK/运行时文档已增加入口，历史阶段记录继续保留。
