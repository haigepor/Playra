# Playra 架构说明

## 分层

```text
界面壳（shell/）
  └─ 路由注册（app_module.dart）
       └─ 业务页面（pages/discover、calendar、detail、favorites、profile、player）
            └─ 数据源契约（features/sources/core/media_source.dart）
                 └─ CliCli 实现（features/sources/clicli/）
                      └─ esdk-v3 协议与传输（protocol/、clicli_client.dart）
                          └─ Dio / 平台网络
            └─ 播放会话（playback/playback_session.dart）
                 └─ 播放器控制器（pages/player/）
                      └─ 播放服务（services/player/）── media_kit / 原生平台
```

## 关键边界

- `MediaSource` 是唯一的内容源接口：`loadHome`、`loadCategories`、`browse`、`search`、`loadDetail`、`loadQualities`、`resolvePlayback`。
- `MediaItem` / `MediaDetail` / `MediaRoad` / `MediaEpisode` / `MediaPlaybackSource` 是页面唯一依赖的归一化模型，CliCli 的 wire field 不得泄漏到页面层。
- `PlaybackSession` 只描述“正在播放什么”：标题、线路、选集、封面、来源显示名；不包含来源协议、弹幕、下载或同步。
- `PlayerController` 只管理播放器资源：创建/销毁 media_kit、音量、倍速、截图、音频会话和外部播放器。
- `PlaybackInitParams` 是页面到播放器唯一的输入：URL、请求头、referer、起始偏移、CENC 密钥、HLS/自动格式。
- 存储层使用三个 Hive Box：`setting`（设置）、`playback_history`（播放历史）、`favorites`（追番收藏）。新增业务必须使用显式键与独立模型，不复用旧来源身份。

## 页面与路由

| 路由 | 页面 | 说明 |
| --- | --- | --- |
| `/` | `ShellPage` | 手机底部 Dock / 平板 72dp 侧栏，四标签（发现、日历、追番、我的） |
| `/browse` | `BrowsePage` | 分类分页浏览，支持综合/最热/最新/评分排序 |
| `/search` | `SearchPage` | 关键词分页搜索 |
| `/detail` | `MediaDetailPage` | 详情、线路、选集、续播、收藏 |
| `/play` | `SourcePlayerPage` | 按需解析短时效播放地址并交给播放内核 |
| `/player` | `PlaybackDemoPage` | 公开 HLS 测试流演示 |

## 设计系统

- `PlayraTokens`：全局颜色、间距、字号、圆角、触控尺寸与动效 token。2026-11-19 起统一为淡紫编辑风。
- `PlayraHomeTokens`：首页与日历的页面级 token（背景、卡片、搜索框、强调色等）。
- `PlayraBackdrop`：所有主页面共享的淡紫渐变与装饰纹理背景。
- `PlayraPageHeader`：搜索、分类、追番、我的等页面的统一编辑式页头。

## 新页面接入约定

1. 页面通过 `app_module.dart` 注册，路径保持语义化。
2. 页面通过 `mediaSources.primary` 或显式注入的 `MediaSource` 发起请求；失败/取消状态由页面持有。
3. 只有“准备播放”这一步调用播放器，不要在播放器内部发来源请求。
4. 选集切换通过 `PlaybackSession.selectEpisode` + 重新初始化，不要复用旧媒体。
5. 需要共享状态时优先使用构造函数注入；全局单例只用于设置、日志和网络基础设施。
6. 新页面使用 `PlayraBackdrop` + `PlayraPageHeader`，不要在页面内硬编码颜色或圆角。

## 当前边界与后续

- 目前只有 CliCli 一个内容源；多来源仅在 `MediaSourceRegistry` 接口层成立，UI 尚未提供来源选择器。
- `MediaSection.layout` / `rows` 仍只做展示层参考，首页当前统一使用横向栏目轨。
- 收藏/历史尚无 schema 版本，模型变更时需要自行做兼容。
