# 首页加载流畅度优化（2026-10-16）

## 范围与约束

本轮承接已完成的卡顿诊断。保持页面 token、布局、SDK 优先级与稳定展示位置；不修改供应商算法、设备指纹、短效播放缓存、历史收藏库或自定义规则。

## 实现

| 文件 | 改动与影响 |
| --- | --- |
| `lib/services/source/lumina/lumina_home_controller.dart` | 首页、其他频道及后续页统一 12 条窗口；其他频道逐个预热。首屏缓存继续供热播取前十条，不新增榜单目录请求。 |
| `lib/presentation/modern/pages/discover_page.dart` | 主频道真实首帧提交后开始频道预热，避免首屏提交前同时堆入多个大目录。 |
| `lib/presentation/modern/home/home_frame_updates.dart` | 合并同一帧内的来源通知；不改变真实请求完成、错误与回退状态。 |
| `lib/presentation/modern/home/modern_home_controller.dart` | 历史更新与按作品分组的排期补全通知独立于首页内容通知。 |
| `lib/presentation/modern/home/modern_home_view.dart` | “继续观看”独立监听且复用为 builder 的 child；排期只更新对应海报；保持原排版。 |
| `lib/presentation/modern/home/home_display_session.dart` | 缓存 ID 集合和不可变展示快照；无新增身份时复用快照，顺序规则不变。 |
| `lib/bean/widget/content_skeleton.dart` | 增加静态骨架选项，保留其余骨架原有动效设置与无障碍语义。 |
| `lib/bean/card/network_img_layer.dart`、`lib/presentation/modern/player/sdk_rank_section.dart` | 独立图片、榜单空槽位不再分别驱动持续脉冲；保留尺寸、颜色、圆角及已有解码尺寸限制。 |
| `tool/web_backend/static_assets.cjs`、`server.cjs` | 静态资源以 ETag 校验，未改变返回 304；入口/资源改版后重新取回；API/运行桥仍 no-store。 |
| `tool/start-web.ps1`、`.github/workflows/release.yaml` | 正式 Web 构建与发布使用随包 CanvasKit，不依赖外部引擎 CDN。 |
| `test/home_load_budget_test.dart`、`test/lumina_content_test.dart`、`tool/web_backend/static_assets.test.cjs` | 覆盖固定分页/不漏项、榜单复用、帧通知合并、局部通知、静态骨架与缓存改版。原总数 25 的目录按 12 条窗口应在第三页结束，补齐其边界断言。 |
| `openspec/changes/integrate-lumina-anime-prepared-playback/tasks.md` | 记录本轮已确认的性能实施与验收任务。 |

## 已完成的静态和行为验证

- 全量 Flutter：767 项通过；最终专项回归：36 项通过。
- Web 后端：39 项通过，包括未改资源 304、改版后返回新内容、HEAD 以及 API no-store。
- 受影响 Dart 文件及新测试：analyzer 无问题。
- Lumina 私有导入摘要校验通过，供应商算法未修改。
- OpenSpec 严格校验通过。
- Web release 构建通过；实际请求确认引擎 JS/WASM 同站点。
- 在独立测试服务 `http://127.0.0.1:18982` 实测静态 ETag/304；原 `18972` 浏览器存储未迁移、未清除。旧进程需正常重启后才应用新的 Node 服务逻辑；其读取的 Web 构建文件已经更新。

## 性能测量与平台验收

Web 统一约 22 秒窗口、1200×900、release、禁用 HTTP 缓存，避免以热缓存对比冷启动；运行期不与构建并行。优化前两轮有效基线、优化后三轮有效采样如下。另有优化前/后各一轮出现约 1 秒周期 RAF 限频，未用于帧间隔比较；首次调整窗口前的试跑也不计入。

| 指标 | 优化前 | 优化后 |
| --- | --- | --- |
| 首次 SDK 请求发出，中位数 | 6230ms | 1069ms |
| 22 秒内主线程非 idle 采样累计，中位数 | 6281ms | 3233ms |
| 每轮 >50ms RAF 间隔 | 10、11 | 6、5、5 |
| CanvasKit WASM 获取耗时 | 3833～6740ms，外部地址 | 21～25ms，同站点，禁用缓存仍实际传输约 5.43MB |

这些是该机器与网络条件下的合并优化结果，不是各项优化的独立贡献或全设备性能承诺。首次 SDK 请求发出并非真实内容就绪时间。优化后仍记录 117～150ms 的最大 RAF 间隔，不能宣称完全没有长帧。浏览器非 idle 采样也不等于总 CPU 用量或 GPU 帧耗时。

实际请求记录确认 Lumina 首页和其他频道均请求 12 条；未出现热播重复请求 10 条目录。推荐四卡在可读状态下的作品与坐标保持不变，推荐/热门切换可用；1200px 与 390px 截图完成，移动视口无横向溢出。控制台仍存在既有更新检查 404，部分 Bangumi 外部接口也可能 502；未观察到本轮引入的 Flutter 布局异常。

Android 采用雷电模拟器与原应用数据覆盖安装；另用独立 profile 入口收集 Flutter FrameTiming，不把普通 Android View gfxinfo 当作 Flutter 流畅度证明。实体 ARM64 手机不在当前可用设备中。

三轮均在冷进程启动后执行六次向下浏览手势，收集约 24 秒：

| 轮次 | 帧数 | UI build P95 | raster P95 | >50ms UI build 帧 | >50ms raster 帧 |
| --- | --- | --- | --- | --- | --- |
| 1 | 248 | 4.296ms | 19.016ms | 0 | 1 |
| 2 | 244 | 2.955ms | 16.580ms | 0 | 1 |
| 3 | 268 | 3.021ms | 17.320ms | 0 | 0 |

第五秒之后三轮 UI build 均无 >16.7ms 帧，raster 均无 >50ms 帧；栅格 P95 分别为 18.633/16.360/6.616ms。加载期 UI 主线程表现可用，但冷启动栅格仍有 36～91ms 峰值，尚未独立归因到贴图、字体或模拟器 GPU。旧 release 没有 FrameTiming 埋点，所以不把新 profile 的数值与旧版 SurfaceFlinger FPS 直接作性能增幅比较。

安卓覆盖前后实际四张推荐卡的作品身份和坐标一致。正式 release 已覆盖安装成功，推荐/热门可切换；历史仍为 6 条、收藏仍为 2 部，《沧元图》第99集 5:52、《唐探1900》1:09 和《毒液：最后一舞》0:21 保留。自定义规则及其存储、迁移代码本轮未修改。

profile 首次构建耗时 481 秒。切回 release 时使用 `--no-pub` 曾导致生成注册文件残留 dev 插件 `flutter_native_splash`，与当前 Flutter release 的 dev 插件过滤不一致。随后使用正常 `flutter build apk --release --dart-define=PLAYRA_DIAGNOSTICS=false` 重新生成插件注册；不修改供应商 SDK 或业务依赖来绕过此问题。构建与会改写插件注册的 Flutter test 命令必须顺序运行。

最终 release 构建 33 秒，通过 ZIP 全量 CRC 与 APK v2 签名验证；已确认正式 AOT 中不含 profile 测量入口标记。产物 `build/releases/Playra-2.3.8-home-smoothness-20261016.apk`，124,751,866 字节，SHA-256：`a546ccdcd9f05a7f742cb31838bc7d12b386b57bf1f06934e0e02bd45dc346d5`。

旧 `18972` 服务的停止操作被自动审批拦截（工具仅返回 blocked by policy，没有更具体原因）。因此保留旧进程，在 `18982` 完成新版 Node 缓存验证；原端口的 IndexedDB 和历史均未移动。实际部署需使用新启动的 Node 进程，不能只替换前端文件便认为缓存头也已更新。

## 回退与本地证据

仅本轮的修改前快照位于 `.dart_tool/home-smoothness-20261016/baseline/`，差异为同目录 `change-only.patch`。这些是工作树原有未提交改动上的增量；回退时不能用 `git reset` 或从 HEAD 整文件覆盖。

同目录保存完整测试日志、性能 JSON、安卓截图与编码/范围记录，均未加入 Git。profile 测量入口只在该忽略目录中，正式 release APK 使用正常 `lib/main.dart`。
