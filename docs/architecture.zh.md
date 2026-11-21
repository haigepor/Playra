# 空壳架构说明

## 分层

```
界面壳（shell/）
  └─ 路由注册（app_module.dart）
       └─ 业务页面（未来新增）
            └─ 播放器组件（pages/player/）
                 └─ 播放会话（playback/playback_session.dart）
                      └─ 播放器控制器（pages/player/player_controller.dart）
                           └─ 播放服务（services/player/）
                                └─ media_kit / 原生平台
```

## 关键边界

- `PlaybackSession` 只描述“正在播放什么”：标题、线路、选集、封面、来源显示名。
  它不包含 Bangumi ID、弹幕、历史、下载或网络协议。
- `PlayerController` 只管理播放器资源：创建/销毁 media_kit、音量、倍速、截图、
  音频会话和外部播放器。
- `PlaybackInitParams` 是页面到播放器唯一的输入：URL、请求头、referer、
  起始偏移、CENC 密钥、HLS/自动格式。
- 存储层只有 `setting` Box。新业务需要持久化时必须新增 Box 与显式键，
  避免再次把来源身份耦合进播放器。

## 新页面接入约定

1. 页面通过 `app_module.dart` 注册，路径保持语义化（如 `/detail/:id`）。
2. 页面自行负责来源请求，失败/取消状态由页面持有。
3. 只有“准备播放”这一步调用 `PlayerController.init`，不要在播放器内部发请求。
4. 选集切换通过 `PlaybackSession.selectEpisode` + 重新 `init`，不要复用旧媒体。
5. 需要共享状态时优先使用构造函数注入；全局单例只用于设置、日志和网络基础设施。

## 已删除但可重建的能力

| 能力 | 重建建议 |
| --- | --- |
| 搜索聚合 | 新建 `lib/features/search/`，按来源并行请求并在页面合并 |
| 收藏/历史 | 新 Box + 新模型，使用来源自己的稳定 ID |
| 弹幕 | 独立 `features/danmaku/`，播放器只暴露时间轴回调 |
| 下载 | 独立下载管理器，输出本地文件后交给 `PlaybackInitParams(isLocalPlayback: true)` |
| 同步 | 独立同步服务，不进入播放器与会话模型 |
