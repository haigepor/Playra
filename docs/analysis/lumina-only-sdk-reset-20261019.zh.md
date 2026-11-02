# 清理全部旧接口 SDK，重建单 Lumina 接入

> 执行状态已更新：当前代码采用 Dart + C，旧 Python 链已退役；以 [原生迁移验收](../verification/lumina-native-reset-20261019.zh.md) 为准。下文保留执行前的分析与范围依据。

日期：2026-10-19。范围：Playra 项目中的内容/播放接口 SDK。按用户最新要求，替换此前“保留多 SDK 并迁移 Lumina”的方向，分析先清理旧接入、再仅接新版 Lumina 的方案。

**本轮产出为依赖核查和清理方案，尚未删除 SDK、修改业务代码或替换已安装 APK。** 当前工作区仍有上一轮升级的未提交修改，实施时必须同时备份这些修改和 Git 忽略的私有输入，不能用整体 reset/clean 抹掉。

## 1. 目标和边界

最终默认内容、搜索和 SDK 播放仅登记 `lumina`，其来源为 `C:/Users/zhuyi/Desktop/tv-reverse-com.tudou.tool-api`。新接入采用 Dart 协议/网络层与按平台交付的 C 引擎，APP 不包含 CPython、Chaquopy 和旧供应商 Python 资产，不再要求设备桥或 Python 服务。

这里清理的是 MioMedia、AniFive 和旧 Lumina 的执行/集成代码，包括本轮已添加但仍依赖 Python 的 Lumina 接入。不会删除外部新 SDK 源目录，也不会删除播放器、Bangumi 资料、ECH/HTTP、UI 基础组件或存储框架。

默认只登记 Lumina，不再将旧 SDK 或普通规则自动混入新 SDK 的搜索/播放结果。普通规则引擎及用户自定义规则可作为既有基础能力保留；保留这些文件不表示它们仍是新 Lumina 的数据来源。未收到清除用户数据要求，不自动删除已安装规则、历史和收藏。

保留共享播放模型、选线/画质/播放器会话及详情页面，去掉其中供应商耦合。旧供应商专属 UI 与公共组件同处 `miomedia/`，应先辨认并迁出公共组件，再删除旧目录。

## 2. 必须同步清理的层级

| 层级 | 当前依赖位置 | 清理要求 |
|---|---|---|
| 私有输入 | `tool/source_runtime/vendor/miomedia/`、`anifive/`、旧 `lumina/`，三类收据 | 从项目执行/构建路径移除；原始算法参考与回滚材料放执行路径之外 |
| 供应商业务层 | `lib/services/source/miomedia/`、旧 `lumina/`；`content_providers.dart` | 删除旧服务与注册；新 Lumina 通过独立执行器接同一公开业务模型 |
| 首页与榜单 | `discover_page.dart`、`modern_home_view.dart`、`sdk_rank_controller.dart`、`modern/miomedia/` | 去掉 Mio 初始化、目录、榜单和回退；只呈现新 Lumina 已确认频道，不留下持续加载的空入口 |
| 个人库入口 | `sdk_library_models.dart`、`sdk_library_widgets.dart` | 解除旧服务调用，保留旧记录可读与不可用状态，不猜测跨站作品映射 |
| AniFive 兼容 | `bundled_anime_migration.dart`、`source_sdk_group.dart`、旧规则中的 runtime 标记 | 取消旧桥执行，处理受管旧规则与用户修改规则；保留完成旧数据识别所需的最小迁移逻辑 |
| Python 执行宿主 | `tool/source_runtime/`、`SourceRuntimeBridge.kt`、`lib/services/source/runtime/` | 断开所有调用方后移除旧运行链；通用网络/解析边界需要在新 Dart 执行器实现 |
| Android 构建 | `android/settings.gradle`、`android/app/build.gradle`、原生桥注册 | 删除 Chaquopy、Python 源集、旧 jni 暂存与私有 Python 输入门禁；独立接原生引擎包 |
| Web/BFF | `runtime.cjs`、`server.cjs`、`start-web.ps1`、来源 HTTP 服务 | 移除启动/转发 Python 的依赖；保留静态服务、图片/媒体代理和 ECH；Web 的 Lumina 接入指向新受控 BFF |
| CI 与工具 | `.github/workflows/release.yaml` / `pr.yaml`，SDK 导入/测试/构建工具 | 删除退役 SDK 输入恢复和回归要求；替换为原生产物校验与 Dart/C 测试，不继续要求 Mio/AniFive 私有包 |
| 文档与测试 | SDK 接入规范、构建输入说明、供应商测试 | 更新当前架构；历史报告保留并标记为历史，删除退役执行器专用测试，保留可复用的契约/播放器回归 |

不能按目录名或 `sdk_` 前缀整批删除：`sdk_player_detail_page.dart`、`sdk_playback_*`、个人库等公共组件仍被 Lumina 使用。旧 Python 的 `RuntimeContext`、地址/重定向检查、响应大小与超时限制也不能在新实现中丢失。

## 3. 功能和数据影响

- MioMedia 当前仍提供影视、漫剧、剧集及动漫备用结果。删除它会移除这些来源；新版 Lumina 没有验收的能力不自动补成“同等支持”。
- 旧 Mio/AniFive 历史、收藏继续可读，来源显示“已移除”，取消自动播放与旧接口请求；不按片名转写为 Lumina ID。
- 旧 Lumina 的 `providerId=lumina`、真实作品 ID、原始 `part`、播放进度与画质偏好优先保持兼容。设备身份文件也应保留，由新实现明确读取迁移，不能因去掉 Python 换一个随机身份。
- 只清理代码和构建输入，不执行应用卸载、清除应用数据或批量清空 Hive/规则。
- 首页频道、榜单、搜索来源、收藏跳转、自动选源都需一起验收；仅确认没有 import 错误不能说明功能完成。

## 4. 新链路应独立于旧 Python 宿主

```text
现有页面 / 公共作品、线路、集数、播放会话
                 ↓
         Lumina 业务执行器（仅七项操作）
                 ↓
      Dart 配置、身份、鉴权、信封、HTTP、播放解析
                 ↓
      长驻工作 isolate → 固定 C ABI 适配层
                 ↓
       当前平台的 _fuse 原生引擎与镜像

Web 客户端 → 同源 BFF → 同一业务契约的 Native 服务端实现
```

业务操作固定为 `config/channels/banners/catalog/search/detail/play`。页面不直接调用密码函数，网络继续支持预算、取消和大小限制，集名不按展示序号重建。保留 4K 优先、手动画质、真实首帧和短时直链刷新。

`LuminaService` 现有 `LuminaRequest` 注入点可以作为复用边界，但默认构造必须改到新执行器，不能继续隐式创建旧 `SourceRuntimeClient`。不把新的本地调用再包装成本机 Python HTTP 服务。

Native 客户端不依赖 Python；Web 浏览器本身不加载这些动态库。BFF 可用 Dart Native 执行新包，Python 仅保留为开发机离线对拍参考，不作为应用运行或 SDK 正式构建前提。仓库其他通用 Python 工具是否继续存在，不属于“APP 内含 Python”的判断。

## 5. 新 SDK 输入仍需补齐

此前分析不能因清理旧代码而跳过。当前 SDK 已有 Windows x64、Android ARM64/x86_64、Linux x64/ARM64、macOS ARM64 六种引擎，但仍有这些缺口：

| 输入 | 当前核验结果 | 接入要求 |
|---|---|---|
| 权威 C 头文件 | 包内没有引擎 `.h`；只有桥接/验证用 C 文件 | 提供 `lumafuse_engine.h` 或等价头文件，明确导出、调用约定、长度与缓冲区契约 |
| C ABI 语义 | 六种产物均核验到 21 个 `lumafuse_*` 符号；Python 只声明 14 个 | 符号存在不证明签名；未声明的 7 个符号不得猜测调用，尤其 `lumafuse_determine_C` |
| 类型与生命周期 | Python 部分返回类型为 `c_long`，引擎共享进程级状态 | 项目适配层返回固定宽度状态/长度，明确所有权、初始化、串行化和错误行为 |
| iOS 产物 | 没有设备或模拟器 `.a` / framework / XCFramework | 至少补 iPhoneOS ARM64 与 iPhoneSimulator ARM64；需支持 Intel 模拟器时再加 x86_64，平台切片必须区分 |
| macOS 最低版本 | 现有 dylib 声明 macOS 13.0，APP 工程目标仍为 10.15；缺 Intel 引擎 | 不为一个 SDK 擅自抬升整个 APP 最低版本；补兼容产物或在不支持组合中明确不登记 Lumina |
| Linux libc | 现有两个库 `DT_NEEDED` 为 `libc.so` | 需要明确 glibc/musl 与最低运行基线，在目标发行版实际加载；不能只凭文件名声明兼容 |
| 镜像与校验 | 引擎镜像解压约 83.6MiB | 摘要、版本关联、冷解压、磁盘与内存峰值需验收；不把它当小型纯算法库 |

原生头文件可由 SDK 提供方确认现有产物接口，不必先要求全部生成 C 源公开；iOS 产物必须由具备源码/构建输入及 Mac/Xcode 的一方补编。Windows 端可以先开展已知接口的最小加载验证。

## 6. 按“先清理，再重接”的执行顺序

1. **归档**：保存当前两个仓库差异、私有 SDK、收据、已安装 APK 对应产物及数据迁移基线；不做整体 reset 或不可恢复删除。
2. **清理旧接入**：移除全部旧供应商注册/执行链与 Python 构建依赖，同步处理页面、榜单、个人库、规则兼容与 Web/CI。交付可编译、可启动的基础 APP；新 Lumina 尚未可用时明确显示未接入，不发旧 SDK 请求。此中间包不作为功能完整版本发布。
3. **原生最小闭环**：冻结权威头文件、固定 ABI 与产物清单，先 Windows x64，再 Android x86_64/ARM64；验证初始化、鉴权、块加解密及错误边界，不引用任何 Python 执行桥。
4. **Dart 协议和七操作**：迁移现有协议行为，与外部 SDK 固定向量及响应夹具逐字节对拍，接搜索、详情、播放、选线和画质。外部 Python SDK 仅作对照，不进入 APP。
5. **平台与性能门禁**：雷电分 ABI 实际播放、同密文解密与冷启动测量；具备对应产物/环境后再验 Linux、macOS、iOS。不存在的产物不生成假能力声明。
6. **最终删净与构建验证**：检查运行代码/APP 资产不含旧 Mio/AniFive/Python SDK 与 Chaquopy；新构建不需要旧私有包；旧历史可读且不请求退役来源；保留单独回滚归档。

本方案不采用长期双 SDK/双 Python 运行链。归档保留在执行路径之外；清理和新接入分别验收，便于定位失败。

## 7. 性能不能只看“去掉 Python”

上一轮雷电 ARM64 同密文 20 次热态样本：官方直载解密 p50 为 38.161ms，`_fuse` 为 954.429ms。移植 Dart 并不会自动消除 `_fuse` 的标定计算。新的 ARM64 路径须用同设备/同密文对照当前直载基线，不能把去掉解释器当成已经提速。

若 `_fuse` 无法满足性能门禁，应在新的 C 适配层补 ARM64 可选直载能力，继承超时隔离、迟到回调和缓冲区生命周期约束；依然不依赖 Python，也不恢复设备桥。该加速路径不是 iOS/桌面的共同前提。

## 8. 验收和当前状态

| 项目 | 状态 |
|---|---|
| 清理范围、公共组件耦合、数据与跨端缺口核查 | DONE |
| 项目代码/SDK 删除和基础 APP 构建 | NEXT |
| 单 Lumina 的 Dart/C 实现与雷电验收 | NEXT |
| iOS 本地引擎接入 | BLOCKED：缺供应商产物和对应构建/设备验收环境 |

现有 SDK 接入规范中的多 SDK 默认登记和 Python 宿主要求是旧架构现状；用户本次单 SDK、Dart/C 重建要求优先。正式实施时须同步更新规范，不能让新实现受旧接入路径反向约束。

本轮仅新增本文档，未改变运行行为。删除本文档即可回滚本轮文档变更；此前 SDK 升级代码与原始备份保持原样。前期原生检查原始输出位于 `.dart_tool/lumina-dart-c-design-20261019/`，上一轮运行证据见 [升级验收](../verification/lumina-upgrade-20261019.zh.md)。
