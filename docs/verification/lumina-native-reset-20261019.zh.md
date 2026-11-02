# 清理旧 SDK 并接入 Lumina Dart + C：执行验收

日期：2026-10-19。工作基线：Playra `02fcd555` 加执行前工作区修改；外部 SDK 参考提交 `88109b2`。本次未提交 Git、推送或发布。

**已先备份、移除旧接口 SDK 与 Python 应用运行链，验证无 SDK 基础包，再仅重新接入 Lumina 的 Dart + C 链路。Android 两种 ABI 已实机型模拟环境验收，Windows 原生模块通过向量及真实接口验证。线路解析仍有明确性能瓶颈，不能宣称已经完成提速；iOS 引擎尚无产物。**

## 1. 备份、数据和回滚

持久备份位于 `D:/project/Playra-backups/lumina-reset-20261019-113222/`，不是仅放在可能被清理的 `.dart_tool` 中。包含：

- `project-before.zip`：执行前文件快照，包含原有未提交修改与 Git 忽略的私有输入；1,507 个文件，备份后逐文件核对摘要。
- `sdk-reference-before.zip`：外部 SDK 参考备份；原始外部 SDK 未删除。
- `installed-before.apk`：替换前的模拟器安装包，59,495,676 字节。
- `inventory.json`、`changes-before.patch`、`status-before.txt`：回滚材料和执行前状态。
- `baseline-no-sdk.apk`：43,329,303 字节的无 SDK 基础验收包。
- `lumina-native-input.gz`：当前私有原生构建输入，SHA-256 为 `c96cf066ae512692cda1773a44814093f4bed80ad1f97916557b92b58e81f3bb`。
- 最终分 ABI APK、验收日志、摘要和本次变更清单。

覆盖安装沿用包名及现有本地测试签名，未卸载、未执行 `pm clear`。模拟器 `firstInstallTime` 仍为 `2026-10-13 17:35:25`，原持久 Lumina 设备身份摘要与迁移前相同。历史记录和 Bangumi 资料继续显示，测试中产生的播放进度正常保存。应用私有数据库原位保留；由于安装包不可 `run-as`，没有声称已取得可离线恢复的完整私有数据备份。

需要回滚时，先另存回滚时点的新修改，再从 ZIP 在独立目录恢复执行前代码和私有输入，按清单核对后替换相关文件；用同签名旧 APK 覆盖安装。不用整体 `git reset --hard` 或卸载来恢复，避免损失用户的新修改和应用数据。当前变更没有调整历史存储 schema。

## 2. 移除与保留范围

| 文件或模块 | 处理及目的 | 影响 |
|---|---|---|
| `tool/source_runtime/`、旧导入/集成脚本、私有 vendor | 从执行路径退役并保留备份 | 不再加载 MioMedia、AniFive 或旧 Lumina Python 模块 |
| `lib/services/source/runtime/`、`SourceRuntimeBridge.kt` | 删除旧 Python/HTTP 执行宿主 | 应用不再启动或连接旧算法运行链 |
| `android/settings.gradle`、`android/app/build.gradle`、`MainActivity.kt` | 移除 Chaquopy 和桥注册；保留原播放器/网络通道；配置分 ABI 原生打包 | 包名、签名身份和播放器基础能力保留 |
| `lib/services/source/miomedia/`、`presentation/modern/miomedia/` | 删除供应商业务与 UI 耦合 | 默认来源仅 Lumina；原共享播放器组件迁到 `modern/player/` |
| `content_providers.dart`、首页/榜单/搜索/详情/个人库接入文件 | 解除旧 SDK 调用、取消无内容分组 | Lumina 展示真实动漫目录；Bangumi 资料和基础页面继续可用 |
| `source_display_names.dart`、旧规则执行边界 | 保留识别旧来源所需的最小兼容 | 旧记录显示“已移除来源（记录保留）”；不按片名猜测新来源身份 |
| `packages/lumina_engine/` | 新增 Dart 协议、解析器、C FFI、构建 hook、摘要清单及 ABI 说明 | 七类操作保持现有业务返回结构；无 Python 回退 |
| `lumina_executor*.dart`、`lumina_service.dart` | 新增单长驻 worker、设备身份和总超时边界 | 主 UI 不直接执行 C；取消只丢弃迟到结果，不中止已运行的 C 调用 |
| `pubspec.yaml`、`pubspec.lock`、`.gitignore` | 仅引入本地 `lumina_engine` 包和按平台私有资产；忽略私有输入 | 未升级其余应用锁定依赖 |
| `tool/web_backend/server.cjs`、旧 runtime 模块、启动工具 | 删除 Python 宿主依赖；退役路由明确返回 410 | 静态服务、图片/媒体代理及 ECH 基础能力保留 |
| `tool/lumina-native-input*.cjs`、CI 工作流 | 固定白名单与 SHA 恢复原生构建输入 | 远端需配置新的私有输入 Secrets；没有自动上传私有文件 |
| `test/` 相关调用方 | 移除退役接口测试，补原生协议/宿主/身份/导航验收 | 保留播放器、历史及 Bangumi 回归 |
| 构建与分析文档 | 更新现行入口、平台边界和性能报告 | 原 Python 分析保留为历史证据，不作为当前速度结论 |

完整工作区变更清单及与执行前 ZIP 的差异保存为备份目录 `changes-after.json`。执行前已存在的修改也保留在快照中；未借清理覆盖其他用户修改。

## 3. 新运行架构及契约

正常入口仍为 `config / channels / banners / catalog / search / detail / play`。Dart 负责鉴权字段组装、RSA 信封、已核验 AES/F、HTTP 和解析器参数处理；C 引擎执行供应商块算法和标定。仅绑定 7 个已经核实的符号，不推断其他导出函数签名。

`include/lumina_used_abi.h` 是本项目根据原绑定写出的接入声明，并非供应商正式头文件。C `long` 使用 FFI `Long`，输出缓冲由调用方管理；C 调用同步返回后才释放。引擎存在全局状态，只由一个工作 isolate 持有。总请求预算涵盖初始化、排队、网络和 C 调用；不能将 Future 超时说成原生执行被立即终止。

保留真实集名/引用、4K 优先、短时直链和原业务模型。参数白名单、公共地址检查、DNS 固定连接、响应大小上限、HTTP 连接复用和超时均在 Dart 执行。POST 不自动重发。诊断仅在开发开关启用时输出阶段和耗时，不输出密钥、鉴权头或完整播放地址。

私有数据为 profile、压缩镜像及三份平台引擎；SHA-256 固定在 `inputs.json`。镜像是算法运行数据，不是 Python 文件；删除 Python 并不代表可以删掉它。应用解压并校验镜像至数据目录，执行代码仅从 Flutter 原生打包目录加载。

## 4. 验证证据

| 检查 | 结果 |
|---|---|
| 无 SDK 基础包 | x86_64 release 编译、覆盖安装、启动；首页/Bangumi/历史可见 |
| Windows 原生模块 | 8 项协议/原生检查；11 组多长度合成块向量及 3 组固定鉴权向量通过 |
| 真实业务链路 | 七类操作通过；播放 MP4 分段读取返回 206 且含 `ftyp`；总预算超时检查通过 |
| Android x86_64 smoke | 七类操作、媒体读取、预取消和并发请求通过 |
| Android ARM64 smoke | 七类操作、媒体读取、预取消、执行中取消与迟到结果隔离、并发请求通过 |
| 正常应用 ARM64 UI | 首页、详情、实际 4K 首帧、切 1080p、换集通过；实际解码尺寸分别为 3840×2160 / 1920×1080 |
| 正常应用 x86_64 UI | 首页、详情、实际 4K 首帧通过；执行本次性能复现后恢复正式普通入口 APK |
| 最终普通入口 x86_64 包 | 覆盖安装并启动；仅“全部/动漫”搜索分组；旧进度保留；实际 3840×2160 视频画面 |
| Flutter 回归 | 一轮完整 703 项通过；随后 20 项原生/协议/导航定向检查和 8 项搜索检查通过，重叠项不累加为独立用例数 |
| Node / 构建工具 | 网关 38 项、原生输入 3 项、通用云构建工具 5 项通过；4 个 PowerShell 脚本解析通过 |
| 最终静态分析 | `flutter analyze --no-fatal-infos` 退出 0；110 条 info，无 error/warning，不将其声称为零 lint 提示 |
| APK 静态核对 | 两种 ABI 各仅含目标架构；引擎 ELF machine、库/资产 SHA 与清单一致；无 Python/Chaquopy 资产或旧 `libcore.so` |

11 组向量为外部参考 SDK 生成的合成固定输入，覆盖 0/1/15/16/17/64/512/1344/1345/4096/8192 字节，不应误称供应商官方独立测试集。Android 与 Windows 的真实接口计时为单轮功能样本；只有性能专项中标明的 Windows 同密文分段测试具有 20 次热态分位数。

主要日志保存在 `.dart_tool/lumina-reset-20261019-113222/`，交付时将必要日志复制到持久备份目录。当前源码文件编码、差异与私有输入跟踪状态另外检查。

## 5. 产物

最终命令：`flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64 --target lib/main.dart --dart-define=PLAYRA_DIAGNOSTICS=false`。

| APK | 大小 | SHA-256 |
|---|---:|---|
| `app-arm64-v8a-release.apk` | 46,275,920 B | `47b12b0c09b92f1651a95d8499f4bea3d24cfbd97b566c2af8e52b03a68680eb` |
| `app-x86_64-release.apk` | 47,462,065 B | `c90e5526bdd6ee43bb8b2283497168980a6bc4b614fbee3a49cec18279787cf9` |

产物同时保存至持久备份目录。模拟器最后保留 x86_64 普通入口、关闭诊断的版本。目录中较早的 `application-diagnostic.apk` 和 smoke 包只用于验收，不作为最终包。

最终 ARM64 分包已构建并完成静态核对，未覆盖安装成功：Flutter 分 ABI 版本码为 ARM64 `22308`、x86_64 `24308`，模拟器已有后者，系统返回 `INSTALL_FAILED_VERSION_DOWNGRADE`。为保留数据未卸载或强制降级。ARM64 的运行证据来自此前同代码链的 smoke 包与双 ABI 普通入口诊断包，不能冒称最终 ARM64 分包再次安装成功。

两份 `_fuse` 的 ELF LOAD 对齐均为 16 KiB，但当前雷电环境为 4 KiB 页。这里只核对引擎，不据此宣称整包已在 16 KiB 设备验证。ARM64 在雷电上通过 Houdini 执行，性能包含指令翻译成本。

## 6. 兼容与性能边界

- Android arm64/x86_64：当前启用并验收；ARM32 不登记 Lumina。
- Windows x64：原生协议/真实接口通过；未声称完整 Windows 桌面 APP 已编译或验收。
- iOS：缺少供应商引擎和 device/simulator 产物，不登记 Lumina。仍需正式 C ABI、错误/内存/线程契约、iOS arm64 设备和 arm64/x64 模拟器静态库或 XCFramework。
- macOS/Linux：存在候选二进制，但目标最低版本/系统运行库边界未完成验收，不启用。macOS ARM 二进制要求 macOS 13，不能当作 iOS 库。
- Web：基础项目保留；不打包私有原生资产，Lumina 尚无 Dart BFF/WASM 交付。未声称 Web Lumina 可用。
- CI：恢复入口与校验已接线，远程 Secrets 和云端干净构建尚未验证。
- 性能：当前 Android 两种 ABI 均使用便携 `_fuse`，并未加入旧 ARM64 官方库直载加速器。**Python 清除完成不等于解密提速完成。** 逐块标定、预加载排队、切画质重复解析均已复现，详见 [线路性能分析](../analysis/lumina-line-resolution-performance-20261019.zh.md)。

## 7. 任务状态

- DONE：先备份、清理旧接口 SDK/Python 应用运行链，保留播放器/Bangumi/原数据。
- DONE：无 SDK 基础应用编译运行后，只重新接入 Lumina Dart + C。
- DONE：Android 分 ABI 构建/验收、Windows 引擎及真实链路验证、静态输入核对和回滚材料。
- DONE：分析线路慢的原因并保存复现证据。
- NEXT：优化播放优先调度和同集短时多画质复用，重新采集点击到就绪/首帧的分位数。
- BLOCKED：iOS 和统一直接算法 C 引擎交付，缺少供应商产物；云端验收缺少已确认的私有输入配置。
