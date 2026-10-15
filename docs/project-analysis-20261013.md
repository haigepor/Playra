# Playra 分支隔离、官方同步与最新主线分析

核验日期：2026-10-13（Asia/Singapore）。工作区：`D:/project/Playra`。

本次范围：读取实时 Git 和源码、快进同步官方镜像分支、整理项目现状。没有合并官方更新到 Playra main，没有修改应用源码，没有重新运行 Flutter/Python 测试、构建或设备操作。本报告为本地分析产物，本次不新增 main 提交。

## 1. 已完成的分支整理

| 指针 | 当前提交 | 职责/跟踪 |
| --- | --- | --- |
| 本地 `main`、`origin/main` | `92138b0abca834c4227c4c25ea81400b4d839acd` | 用户自己的 Playra 主线；拉取、默认推送均面向 origin |
| 本地 `kazumi-upstream` | `4960f9c04246eb52e1f36728f0f5c60ae6fa54dc` | 官方原版；跟踪 upstream/main，推送到 origin 同名分支 |
| `origin/kazumi-upstream` | `4960f9c04246eb52e1f36728f0f5c60ae6fa54dc` | Playra 仓库内的官方原版镜像 |
| `upstream/main`、官方远程 HEAD/main | `4960f9c04246eb52e1f36728f0f5c60ae6fa54dc` | `https://github.com/Predidit/Kazumi.git` 的最新 main |

Playra 远程为 `https://github.com/haigepor/Playra.git`。本地官方分支和 Playra 远程官方分支均由 `2768c230` 快进到 `4960f9c0`，普通 push 成功。完整 SHA 已由两个远程的 `ls-remote` 返回值核对。

隔离采用用户此前确认的共同祖先方案：保留官方历史，分开分支职责。共同祖先为 `2768c230407d5fd8a57716160ba1a85a99161581`；当前 `main...kazumi-upstream` 为 **15 / 3**，分别表示 Playra 独有 15 个提交、官方独有 3 个提交。

```text
官方既有历史 ── 2768c230 ─┬─ 官方新增 3 个提交 ── 4960f9c0  kazumi-upstream
                        └─ Playra 定制 15 个提交 ── 92138b0a  main
```

同一个 GitHub 仓库保存两个分支不表示文件混合。分支指向不同文件树；`kazumi-upstream` 与官方 main 的提交和文件树完全一致，不含 Playra 定制。此次无需重写 main 或制造无共同祖先的孤立分支。

### 本机默认行为

现有 `branch.main.pushRemote=origin`、`branch.kazumi-upstream.pushRemote=origin`、`remote.pushDefault=origin` 均保留。`upstream` 默认只获取官方 main。

本次仅补充三个仓库本地 Git 设置，避免自动携带 tag：

```ini
remote.origin.tagOpt = --no-tags
remote.upstream.tagOpt = --no-tags
push.followTags = false
```

这是本机 `.git/config` 的配置，不随源码提交传给其他机器。`--no-tags` 关闭自动跟随 tag；显式 tag refspec 和显式推送仍能操作 tag，不能把它描述为权限封锁。[Git 配置文档](https://git-scm.com/docs/git-config#Documentation/git-config.txt-remoteltnamegttagOpt)

### tag 的当前事实

- origin 远程 tag 数为 **0**，本次没有创建或删除远程 tag。
- 本机已有 **129** 个裸名称 tag；逐项核对均与官方同名 tag 对象一致。
- 本机 `upstream/` 前缀 tag 数为 **0**。`docs/release/tag-policy.zh.md` 所述旧机器的本地迁移和 bundle 不等于当前机器已具备这些引用/文件。
- 本次保留本机既有 tag，不额外迁移、删除或推送。后续自有版本沿用 `playra/v*`，发布策略与源码分支同步分别处理。

## 2. 官方本次新增内容

以官方 `2768c230 → 4960f9c0` 的真实差异为范围：**3 个提交、10 个路径、498 行新增、278 行删除**，不是对整个官方项目的泛化说明。

| 提交/日期 | 更新 | 对 Playra 的含义 |
| --- | --- | --- |
| `27c4efe7` / 2026-10-11 | Windows 保持 Flutter accessibility bridge 禁用；拦截 `WM_GETOBJECT`，补 `comctl32.lib` 链接 | 针对上游注明的 AXTree 崩溃规避；涉及 Windows 辅助功能行为，当前 main 尚未包含这段桥接修复 |
| `dc18be2a` / 2026-10-11 | Flutter 声明由 3.47.6 升至 3.47.7，更新 lock 与 fastlane Flutter 子模块指针 | Playra main 仍声明 3.47.6；以后集成时需要整体对齐工具链和锁文件，不能只改版本文本就宣布兼容 |
| `4960f9c0` / 2026-10-12 | 用户选择 GitHub/镜像更新下载源；拆分更新弹窗、来源枚举和下载器 | 可借鉴下载源选择、临时文件、SHA-256 和取消处理，但必须保留 Playra 自有品牌及版本筛选 |

最新提交另外限制未知网络错误获取连接信息的等待时间为 1 秒，降低错误展示被附加查询拖住的风险。更新下载器要求有效 SHA-256，先下载私有临时文件，校验后再移动到目标路径，并对文件处理阶段补取消检查。

来源：[Windows 修复](https://github.com/Predidit/Kazumi/commit/27c4efe7)、[Flutter 升级](https://github.com/Predidit/Kazumi/commit/dc18be2a)、[更新下载源与下载器](https://github.com/Predidit/Kazumi/commit/4960f9c04246eb52e1f36728f0f5c60ae6fa54dc)。

## 3. 合并风险预演

执行 `git merge-tree --write-tree --name-only main kazumi-upstream`，退出码为 **1**。这是仅生成合并树对象的预演，不修改工作区或索引，不新建提交，不进入真实合并状态。[Git merge-tree 文档](https://git-scm.com/docs/git-merge-tree)

双方自共同祖先以来共同改动的路径有四个：

| 路径 | 文本预演结果 | 后续必须保护的内容 |
| --- | --- | --- |
| `lib/services/update/auto_updater.dart` | **冲突** | Playra Release API、`playra/v*` 解析、稳定版本筛选、无自有发布时的 404 行为 |
| `pubspec.lock` | **冲突** | 自有依赖与 path 覆盖，按最终 pubspec 和实际工具链生成，不机械二选一 |
| `pubspec.yaml` | 可自动合并 | Playra 描述、既有 UI/运行时依赖、Flutter 版本一致性 |
| `windows/runner/flutter_window.cpp` | 可自动合并 | Playra 名称/快捷方式与新增辅助功能规避逻辑并存 |

“可自动合并”只说明文本合并，不代表运行兼容。此次保持 main 原样，官方新增功能仅存在于同步分支。

尤其不能用官方 `auto_updater.dart` 整文件覆盖 Playra 版本：官方按自身 tag 判断版本，Playra 使用 `AppBrand.releaseVersion` 筛选 `playra/v*`，且更新地址指向 `haigepor/Playra`。镜像下载选项也只能指向真正属于 Playra 的发布资产，不能借用官方 Kazumi 镜像资产。

## 4. main 最近四个提交

| 提交 | 内容 | 提交规模 |
| --- | --- | --- |
| `4cd72909` | MioMedia 内容/播放运行时、Android 内置桥接及相关界面接入 | 152 个文件，15,453 行新增、240 行删除 |
| `6f92193a` | 发现、榜单、选集、播放体验和故障恢复完善 | 56 个文件，4,929 行新增、1,348 行删除 |
| `16258366` | Playra 品牌、发布策略、私有输入和 CI 整理 | 66 个文件，1,905 行新增、1,686 行删除 |
| `92138b0a` | 完成发布准备任务的提交/推送记录 | 1 个文件，1 行新增、1 行删除 |

这些是文件/文本规模，不是四组独立验收证明。累计相对官方共同基线，Playra 修改/新增 **681 个路径**，其中 lib 300、docs 127、OpenSpec 58、third_party 52、tool 44、assets 38、test 36。该数字包含文档、图像和第三方代码，不应把它全部称为业务代码规模。

**判断：项目已经从以 UI 定制为主，发展为具有独立内容运行时、播放编排和发布身份的分支。** 后续官方集成需要按模块检查契约，不能将整棵官方文件树覆盖 main。

## 5. 当前功能与调用链

### 5.1 两套作品身份与页面

`lib/pages/info/info_module.dart` 先判断参数是否为 `MioVideo`，进入 `MioDetailPage`；`BangumiItem` 继续使用原详情/新版播放一体页路径。MioMedia 作品 ID 保持字符串，线路使用真实 code，剧集使用真实编号，避免混用 Bangumi 身份和显示位置。

发现页既有 Bangumi 动漫内容保留，影视内容通过 `MioHomeController` 与 `MioMediaService` 加载；搜索、分类目录和榜单具有独立状态。七天热播榜使用平台真实模块/原始顺序和分类 ID，不用累计播放量自行排序成“七天榜”。

### 5.2 Android 已内置 Python

当前源码的默认链路是：

```text
Flutter 页面 → MioMediaService → SourceRuntimeClient
    → MethodChannel → Kotlin SourceRuntimeBridge
    → Chaquopy/Python AndroidRuntime → 私有 MioMedia SDK → 平台
```

`runtime_endpoint.dart` 的外部运行服务地址默认为空；Android 的空地址走 `invokeEmbeddedRuntime`。只有显式配置外部端点时才采用外部服务。普通 Android 使用不再依赖开发电脑的 Python HTTP 服务。

因此，早期 `miomedia-content-playback.zh.md` 中关于 Android 默认连接电脑/USB reverse 的段落属于旧阶段运行方式。当前构建入口优先参照 `docs/release/build-inputs.zh.md`、内置运行时源码和新发布记录。

### 5.3 Web 保留同源服务桥接

Web 使用 `/api/runtime/v1/`，Node 桥接只向配置的 loopback Python 端口发送允许的路径。源码限制路径/方法、请求体 32KB、响应 2MB、请求预算，并不转发调用者提供的 Host、Cookie 或任意目标地址。媒体通过既有同源网关处理来源 headers 与 HLS 资源。

当前 Python 公开操作为 11 个，包含内容、搜索、`hotRank` 和 `play`；文档清单中的 132 个平台端点并不代表 APP 已接入全部能力。SDK 算法在服务/内置 Python 内执行，客户端只提交受限业务参数。

### 5.4 播放编排已具备故障保护

`MioPlaybackCoordinator` 按作品会话缓存剧集五分钟并合并在途读取，保留显式线路优先，结合近期结果/耗时排序备选来源。身份匹配拒绝把展示数组位置当作剧集编号。页面使用代次与取消令牌抑制迟到结果，媒体 `stop/open` 串行。

起播成功标记结合 playing、buffering、进度和视频尺寸；来源解析成功或 HTTP 200 本身不等同持续解码成功。仓库记录曾观察 Web 持续播放，但当前手机故障仍需独立定位。

### 5.5 页面细修与品牌整理已提交

`docs/design/modern-secondary-polish.zh.md` 记录人物头像/资料分组、以图搜番图标、图片预览提示、引导装饰比例和搜索状态层级的局部细修，相关代码已进入当前主线。不要再照旧交接提示词机械重做同一批调整。

品牌由 `lib/app_brand.dart` 集中定义。系统可见名为 Playra，旧安装 ID、MethodChannel 和数据路径仍保留，以维持升级数据兼容。Release 默认隐藏诊断/实验入口，关于页提供产品、帮助、隐私和许可说明。

自有更新指向 Playra Release API，版本前缀为 `playra/v`。发布 workflow 接受 `playra/v*` tag 或手动触发，产出 Android/Web 附件，不自动创建 GitHub Release；SDK 输入和正式 Android 签名材料依靠 Secrets。

## 6. 当前最需要继续处理的边界

| 优先级 | 问题 | 依据与建议 |
| --- | --- | --- |
| 高 | 红米 K50 / Android 15 电影播放数秒后失败 | 最新发布记录仍注明“暂时无法取得播放资源”，当前 APK 未完成该手机完整播放验收。后续优先采集脱敏的线路、剧集、阶段、错误类别和耗时，区分 SDK 换取、解析、HTTP/HLS 和实际起播失败；不要直接认定是播放器或运营商问题 |
| 高 | 本机缺少私有 SDK 构建输入 | 当前 `tool/source_runtime/vendor/miomedia/` 不存在；它被发布策略忽略是预期行为。公共克隆不足以直接复现内置 SDK 包，需按构建输入说明提供授权模块与完整数据资源；本轮没有读取或上传私有材料 |
| 高 | 正式 CI 和签名尚未有运行证明 | 发布记录称 SDK 与正式签名 Secrets 未配置/执行。仓库中已有流程，不等于 Actions 已构建成功或正式发布可用 |
| 中 | 官方更新整合有真实冲突 | updater 与 lock 冲突；后续在专门集成分支处理，保护 Playra 发布身份，不改官方镜像分支 |
| 中 | 文档包含不同阶段和机器状态 | 早期 HTTP Android 说明、旧设备“未连接”和旧路径不可直接代表新内置 SDK；旧机器记录的 tag 命名空间、本地 bundle 和 APK 在本机也不能假定存在 |
| 中 | 设备矩阵仍不完整 | Android 模拟器、Windows SDK 调用、Web 解码和 Redmi 真机是不同证据。部分验证记录失败后已有新轮修复，阅读时按日期和最终发布记录判断，不能挑单条成功概括全平台 |

最新发布文档记录：Flutter 528 项测试、分析无 error/warning、SDK 自检、Web/Android 构建和模拟器启动等结果。这些是**已提交文档中的此前验证记录**，本轮没有重跑，也没有把它们扩展为当前机器或红米真机的成功结论。

本机 `.tooling/flutter` 存在，但 `build/releases/` 不存在；不能将旧机器记录的 APK 当作这里可直接安装的产物。

## 7. 后续官方同步方式

继续保持两阶段：先更新纯官方分支，用户要求整合功能时再处理 main。可在不切换当前 main 工作目录的情况下快进镜像：

```powershell
git fetch upstream --no-tags --no-recurse-submodules
git merge-base --is-ancestor kazumi-upstream upstream/main
# 上一步退出码必须为 0；否则先查明原因，不能强制更新。
git fetch --no-tags --no-recurse-submodules . refs/remotes/upstream/main:refs/heads/kazumi-upstream
git push origin refs/heads/kazumi-upstream:refs/heads/kazumi-upstream
```

执行前确认 `kazumi-upstream` 没有被其他 worktree 检出。Playra 集成时遵循 `docs/git-workflow.md` 中的 `codex/kazumi-update-YYYYMMDD` 临时分支方案，先对照官方独有差异，处理冲突后再交付；本轮没有创建这个集成分支或开始真实合并。

## 8. 修改、核验与回滚位置

- DONE：官方本地/远程分支同步，main 指针保持原值；通过远程 SHA、文件树和分支计数确认。
- DONE：本机 Git 默认 tag 行为隔离，既有 129 个 tag 和 origin 的 0 tag 状态保留。
- DONE：读取最新主线源码与记录，进行无工作区合并预演，保存本地分析报告。
- NEXT：用户后续要求时整合官方三项改动，或继续 Redmi 播放故障定位；本轮不追加测试构建。

应用源码没有修改。本报告为新增文档，尚未提交；main 和 origin/main 仍为 `92138b0a`。

同步前 refs 和 Git 配置备份：`.git/codex-backups/upstream-sync-20261013-074610/before.json`、`config.before`、`config-keys.before.json`。三项新增 Git 配置原本均未设置，若之后确需撤销，只逐项移除本次新增键；先检查是否有后续改动，不整体覆盖新配置。

官方旧指针 `2768c230` 仍在两条主线历史中可查。撤销远程快进需要重写远程指针，不能为了回退分析结果擅自强制推送。原 main 代码未变，不涉及应用代码回滚。

预演原始证据保存在忽略文件 `.tooling/upstream-sync-analysis-20261013.json`。这些本机备份与私有输入不进入仓库提交或远程附件。
