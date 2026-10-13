# Web、Android 与 MioMedia SDK 分析

分析基于 Playra `03f34604` 检出及本轮依赖配置。应用界面、播放编排与 SDK 算法未修改。初始工作区已有 `docs/project-analysis-20261013.md`，本轮保留原文件。

## 架构与职责

Playra 是 Flutter 应用，沿用 Kazumi 的 Bangumi、规则、历史、收藏与下载体系；MioMedia 有独立的作品模型、服务与播放页面。

```text
发现 / 分类 / 搜索 / 详情
    → MioMediaService
    → SourceRuntimeClient
        Web：同源 /api/runtime/v1/ → Node 固定桥接 → Python RuntimeServer
        Android：MethodChannel → Kotlin SourceRuntimeBridge → Chaquopy AndroidRuntime
    → MioMediaSdk → 原 SDK Client / PlaybackClient → 上游服务

播放结果 → MioPlaybackCoordinator → MioDetailPage → media_kit
    Web：媒体、HLS 子列表/分片/密钥经同源媒体网关
    Android：原生播放器直接访问媒体，传递来源请求头
```

主要源码：`lib/services/source/miomedia`、`lib/services/source/runtime`、`lib/presentation/modern/miomedia`、`tool/source_runtime`、`tool/web_backend`、`android/app/src/main/kotlin/com/example/kazumi/SourceRuntimeBridge.kt`。

### 已有的可靠性设计

- 作品 ID 保持字符串，线路使用真实 code，集数使用真实 episodeNum；与 Bangumi 身份隔离。
- 接入层只允许 11 个固定 SDK 操作及有限业务参数，客户端不能指定 Python 模块、脚本或任意 SDK 端点。
- 持久身份使用文件锁、同目录原子替换；损坏身份不会自动覆盖。并发首次调用合并握手，会话有效期 300 秒，每个业务调用使用独立 Client。
- 换取播放地址与奖励凭证的消费请求不在网络错误后盲目重复提交；Playra 固定使用 TOKEN 策略，避免 SDK 默认 AUTO 路径重置身份。
- Web 桥接固定指向 loopback；限制方法、请求体 32 KiB、响应 2 MiB 和总预算。Python 最多 4 个执行名额；Android 4 个工作线程、8 个排队名额，取消有独立执行器。
- 页面使用取消令牌与代次抑制迟到结果；剧集按页面会话缓存 5 分钟并合并在途读取；播放器 stop/open 串行。

### SDK 分层

| 模块 | 职责 |
| --- | --- |
| `client.py` | 请求头、校时、握手、业务请求、身份读写 |
| `device.py` / `signature.py` | 设备身份、派生秘密、请求签名与指纹 |
| `transport.py` | v3 wire、算法链、ECSM 分块与会话 seal/unseal |
| `suite.py` / `block.py` | 协议原语与设备指纹块处理 |
| `playback.py` | 凭证、qualities、exchange、客户端解析与媒体结果 |
| `config.py` / `profile.py` | 接入点及平台分配配置；不属于可随意更换的 UI 品牌信息 |
| `_native/__init__.py` | 可选 ctypes 加速桥；动态库不可用时返回纯 Python 路径 |

当前 Playra 的 play 路径依次经过凭证领取、清晰度/换取令牌、播放地址换取，以及必要的客户端解析。它没有执行上游下发的任意 Lua；解析是 SDK 的固定 Python 实现。媒体 URL 返回成功与持续解码成功是不同验收项。

## 本轮确认与处理

### 已修复：SDK 同步/打包丢失加速桥

最初提供的 12 文件压缩包 SHA-256 与用户给出的值一致，ZIP CRC 正常，每个文件与其桌面解压目录一致，但 `suite.py` 导入 `_native` 后启动失败。固定文件检查只检查大小/语法，没有发现运行依赖不闭合。

随后提供的完整项目目录及 ZIP 中包含 `_native/__init__.py`，完整目录自检成功；完整目录和 ZIP 中的 suite、桥文件逐字节一致。Playra 原同步工具会丢掉子包，Android 复制规则也没有纳入它。

本轮只修改输入边界和 Gradle 复制规则：兼容原有无加速桥依赖的 12 文件 SDK，使用加速桥的版本必须包含第 13 个 Python 文件；同步、Secrets 导出/导入和 Android 打包保留这个固定路径。Windows DLL 不进入 APK。安装后的 13 文件与完整原 SDK 对应文件逐字节一致，manifest 已重新记录其哈希，没有修改算法和私有配置值。

## 尚待后续处理的问题

| 优先级 | 结论、证据与影响 | 建议 |
| --- | --- | --- |
| 高 | `transport.py:138–185` 计算 `hmac_ok`，但 `decrypt_v3` 不拒绝 False。离线只翻转 MAC 最后一个字节，解析显示 False，unseal 仍返回原明文。默认接入点使用 HTTP，传输完整性不能因此视为已验收 | 在 SDK 维护范围内补强校验及损坏报文测试；本轮未改原算法/协议代码 |
| 高 | `tool/web_backend/server.cjs` 跨域重定向会删除 Cookie/Authorization，但 HLS 重写仍使用最初的 rawHeaders。离线重放 A→B 重定向，B 播放列表请求没有凭据，而 B 分片 URL 中重新带入 A 的凭据 | 根据最终目标与请求头作用域生成子资源地址；增加重定向到 HLS 的集成测试 |
| 中 | `MioPlaybackCoordinator.play` 捕获所有异常后只记录线路失败；详情页也使用通用错误提示。解析函数把网络/取消错误转换为 unavailable。首页已能显示安全错误码，播放路径仍可能丢失阶段信息 | 保留安全错误码与阶段，区分握手、凭证、换取、解析、媒体网络、解码 |
| 中 | 单次 SDK 请求有 20 秒预算，但播放换线没有整个会话的总 deadline。最多 3 次是实际 play 调用上限；寻找匹配剧集的 episodes 请求不在这个次数内 | 增加整个选集操作的预算；保留剧集缓存的所有权设计 |
| 中 | `_openMedia` 用视频尺寸与超过 200ms 的位置确认起播；起播后的 error 只显示提示，不再次调用换线协调器 | 将持续播放失败纳入可恢复状态机；不能用首次起播证明数秒后的播放稳定性 |
| 中 | 常规 `lib/main.dart` 仅 Android 支持新版界面，Web 新版发现/影视入口在独立 `main_home_preview.dart`。CI 静态 Web 附件没有运行服务 | 明确正式 Web 的产品入口与服务部署范围，独立验收预览、正式构建与部署 |
| 中 | MioDetailPage 独立持有 Player，没有接入 Bangumi 的收藏、历史续播、下载与弹幕上下文，这是当前明确的功能边界 | 后续按 provider 与稳定内容身份接入，不能把 Mio ID 当作 Bangumi ID |

以上离线重放不访问第三方真实内容，不代表攻击或真机故障已经发生。红米 K50 的旧问题仍没有当前真机证据，不能据此认定根因。后台运行时健康/清单返回 200 只证明本机服务可启动。

## 路径与部署结论

此前文档混有不同电脑的用户名、Android SDK/JDK 路径和不同阶段的 Android HTTP 方案。当前规范入口为 [多设备路径与环境说明](../development/web-android-environment.zh.md)：仓库相对路径用于源码与项目工具，本机 JSON 保存共享 SDK 位置，私有输入独立准备，生成产物重新构建，身份各设备分别保存。

当前脚本不修改系统 PATH，桌面旧工具保留。项目的 255 个包和 Flutter 工具的 102 个包已重新解析到 D 盘，包配置没有 C 盘根路径。Windows 系统/MSVC 保持本机注册位置。

## 验证与限制

- 真实 SDK：包模式与目录脚本模式自检全部通过，播放 12/12；13 个文件与原 SDK 字节一致。
- SDK 输入：7 项测试通过；新增测试先复现缺桥/丢桥，再验证同步与 bundle。
- Python 接入：44 项通过；不是依靠此前诊断占位模块的结果。
- Node：11 项通过，包括 D 盘 Chromium 实际运行的动态视频解析与取消检查。
- Flutter：528 项最终全量通过；先前唯一失败为既有预览测试父目录不存在，环境准备已补齐目录，没有改变断言。
- Web Release：构建成功；常规入口产物位于 `build/web`。
- 静态分析：无 error/warning；保留既有 info，不进行无关清理。
- Android：首次构建因 JVM 原生内存分配失败退出；本机限制内存与并发后 Debug 构建成功。最终 APK 为 174,190,904 字节，SHA-256 为 `312d2c801d18a45e4053794e286fc5ba6cefe9187787ef758d0a72f87283e15e`。APK 和内嵌 Python ZIP CRC 正常；三种 ABI 均包含 Python 3.11，`_native/__init__.pyc` 与 4168 字节的 `bf_tables.bin` 存在，表文件哈希与原 SDK 一致，没有 Windows DLL。
- 当前没有连接 Android 真机；未验证真机目录与持续播放，未配置正式签名或发布 Actions Secrets。

路径验证：从仓库外加载环境成功，重复激活 PATH 不叠加；另用含中文与空格的迁移目录验证相对配置解析正确。迁移检查使用占位工具文件，不代表在另一台真实机器完成构建。

## 修改文件、影响与回退

| 文件 | 目的与影响 |
| --- | --- |
| `tool/use-dev-env.ps1`、`tool/dev-environment.example.json` | 新增本机配置入口与可同步模板；按检出根目录解析相对路径，限定当前进程环境与项目缓存 |
| `tool/build-android.ps1`、`tool/start-web.ps1`、`tool/start-home-preview.ps1` | 有本机配置时自动激活，并支持配置的外部 Flutter 工具目录；影响对应启动/构建入口 |
| `tool/miomedia_sdk_input.py`、`tool/test_miomedia_sdk_input.py` | 保留新版 SDK 的固定加速桥子包，拒绝缺桥输入；影响 sync/check/export/import-env，保留旧 12 文件版本兼容 |
| `android/app/build.gradle` | 检查并打包 Python 桥；影响 APK 的 SDK 资源完整性 |
| `tool/source_runtime/vendor/sdk-manifest.json` | 更新本机安装的原 SDK 文件哈希，提供可复核清单，不包含配置值 |
| `.gitignore` | 忽略本次构建生成的 `android/.kotlin` 缓存 |
| `README.md`、`docs/source-algorithm-runtime.zh.md`、`docs/miomedia-sdk-integration.zh.md`、`docs/release/build-inputs.zh.md` | 统一环境入口、移除旧电脑用户名路径，区分内置 Android 与历史 HTTP 阶段 |
| `docs/development/web-android-environment.zh.md`、本报告 | 新增多设备恢复说明、分析与验证边界 |

本机忽略文件还包括 `.tooling/dev-environment.json`、独立 Gradle 资源配置、D 盘工具/缓存、13 文件私有 SDK、Secrets 输入分片和新构建产物；它们分别属于环境、私有输入和产物，不进入 Git 同步。

备份、详细日志位于本机 `.tooling/dependency-setup-20261013` 与 `.tooling/logs`。这些是本机证据路径，不是其他机器的依赖。原工作区报告未覆盖，报告编写时尚未提交或推送此次变更，后续提交记录以 Git 历史为准。回退代码以本轮前 `03f34604` 的对应文件为依据，只撤销本轮差异；本机 JSON 与缓存独立处理，保留身份和签名材料，不对整个工作区执行重置。
