# Lumina 数据源逻辑同步（2026-11-03）

## 结论

Playra 内置的 Lumina 客户端停留在 SDK `88109b2`（2026-10-19）。上游交付包
`jionciyuan/deliver` 已到 `d3d7d93`（2026-11-02，T14 全接口深测 + T15 接入包整备）。
本次把两者逐项对齐，补齐 6 处协议逻辑差异，并用离线向量 + 真连七操作验证；
真连后 `play` 从「必失败」变为 7/7 全通过。

本地门禁：`dart run bin/check.dart` 8/8、`dart run bin/live.dart` 7/7（含首字节 206/mp4）、
`flutter analyze` 0 error/warning。`flutter test` 有 3 个**预存** UI 用例失败，
已用「engine 三个文件回退到 HEAD、其余不变」的 A/B 证伪与本次改动无关（见 §5.3）。

## 1. 差异清单

| # | 项 | 旧实现（88109b2） | 新事实（d3d7d93） | 影响 | 本次处理 |
|---|---|---|---|---|---|
| 1 | 播放 source 分流 | 一律拼 `parser+source` 走解析器 | source 有两类：`http…` 直链型（电影/单片）原样可播；`a\|b\|c\|d` 不透明串才走解析器 | 电影类（如 `vid=217`）必然失败 | `_play` 增加 `source.startsWith('http')` 分支，`kind=direct` |
| 2 | `510423 播放遇到问题` | 直接抛 `BUSINESS_REJECTED` | 服务端瞬态，同参数重试即恢复 | 偶发失败放大成用户可见错误 | 仅对 510423 重试一次（600 ms） |
| 3 | 解析器密钥轮换 | 只用 Lua 下发的 `aes_key/aes_iv` | 服务端轮换 Lua 密钥与解析器加密不同步（2026-11-02 15:11–15:15 实测错位约 4 分钟） | 错位窗口内解析全失败 | 解码按「当前 Lua → 历史密钥表」回退；标准 base64 优先 |
| 4 | 引擎块上限 | 只校验 `≤2 MiB` | Cb 生成器在 ~1944 块后 abort/挂死宿主进程（不可捕获）；服务端分页上限保证正常响应远低于此 | 超大响应会杀掉 App | `LuminaEngine.maxBlocks=1900`；fuse 回落路径先拒绝并抛 `RESPONSE_TOO_LARGE` |
| 5 | core 后端配置缺失 | `hexBytes(null)` 抛 TypeError → worker `ENGINE_UNAVAILABLE` | profile 精简版可能没有通道常量 | auto 模式本可回落 fuse，却整引擎不可用 | `CoreResponseBackend.configured()` 预检，非终态 `CORE_CONFIG` 回落 |
| 6 | 解析器 salt 新形态 | 只认 `salt = "…"` | 新脚本不再下发 `salt` 字段，改为 `sign()` 字面量：`data .. "kvdenozcjy" .. ts` | 取不到真实盐，只能落到兜底值 | 增加 `.. "…" ..` 字面量解析 |

### 1.1 私有输入重建时发现的第 7 项（关键）

重建 `profile.json` 时先按「私钥推导公钥」填写 `_SERVER_PUB_B64`，结果
GET 六操作全通、`play`（唯一 POST）恒定 `BUSINESS_REJECTED`。
实证：**请求信封与响应信封是两对独立 RSA 密钥**（`server_pub_2048_live.pem`
的公钥 ≠ `priv_from_go.pem` 推导出的公钥）。`_SERVER_PUB_B64` 必须用服务端
请求公钥，`_SERVER_PRIV_B64` 才是响应私钥。修正后 play 立即通过。

> 这条也是给接入方的坑：两个字段不能用同一对密钥代入。

## 2. 改动文件

| 文件 | 改动 |
|---|---|
| `packages/lumina_engine/lib/client.dart` | `_play` 分流 + 重试；抽 `_resolveSource` / `_directMedia` / `_streamHeaders`；`parseResolver` 多密钥 + 标准 base64 优先；salt 字面量解析；fuse 回落路径块上限预检 |
| `packages/lumina_engine/lib/lumina_engine.dart` | `maxBlocks = 1900` + 原生调用前守卫 |
| `packages/lumina_engine/lib/core_backend.dart` | `configured()` 预检，非终态 `CORE_CONFIG` |
| `packages/lumina_engine/inputs.json` | `sdkCommit: d3d7d93`、`integrationVersion: 3`、`profile.json` 新摘要 |

播放请求头保持原样（默认 `Referer = 地址本身` + 五个 CDN 域名覆盖）——这是
play 下发 Lua 里 `custom_head()` 的逐条复刻，比交付包 Python 侧的简化版更忠实。

## 3. 私有输入重建

`native/` 与 `assets/lumina_private/` 被 `.gitignore` 排除，CI 靠
`tool/lumina-native-input.cjs restore` 注入。本次重建内容：

- `fuse_core.dll`、`liblumafuse_android_{arm64,x64}.so`、`fuse_image.bin.gz`：
  与 `inputs.json` 原摘要逐字节相同（取自交付包 `engine/`）。
- `libcore_android_arm64.so`：sha256 `26727c7b…`，与清单一致。
- `profile.json`：按客户端实际读取的字段重建（应用标识、认证常量、两对 RSA 公钥/私钥、
  解析器兜底、core 通道常量与 TCP 端点）。摘要写入 `inputs.json`。

`profile.json` 含响应私钥，仍只存在于忽略目录与加密后的私有输入包中。

## 4. 验证

### 4.1 离线向量（`dart run bin/check.dart`）

```
native request bytes=48; expected=48; prefix=true
PASS: 8 protocol/native checks; engine=lumafuse-1.6
```

覆盖：CB64 往返、F 向量、请求加密（与 Python 参考实现逐字节）、响应解密、
authentication（152 字符）、RSA 解 P0、RSA 加密长度、AES 基础向量。

### 4.2 真连七操作（`dart run bin/live.dart`）

```
config PASS 350ms
channels PASS 250ms
banners PASS 476ms
catalog PASS 623ms
search PASS 189ms
detail PASS 198ms
play PASS 2748ms
pre-HTTP cancellation PASS
request budget PASS
```

报告：`mediaCount=1`、`mediaProbe={status:206, bytes:6944, mp4:true}`。

### 4.3 预存 UI 失败（与本改动无关）

`browse_auto_load_test`、`content_skeleton_test`、`modern_profile_test` 三个用例
失败。A/B 证伪：把 `client.dart` / `core_backend.dart` / `lumina_engine.dart`
三个文件 `git stash` 回 HEAD（清单与私有输入保持新值），三个用例**同样失败**。
故与本次协议同步无关，属 2.4.2 合并后的 UI 回归。

## 5. 正式 APK 构建与真机验收（2026-11-03）

### 5.1 构建产物

| 项 | 值 |
|---|---|
| CI run | `41479106377`（workflow `Playra platform build`，`workflow_dispatch`，head `8c94a30a`，conclusion `success`） |
| 构建输入 | 加密私有输入包（release asset，AES-256-CBC/PBKDF2 200k）+ 7 个 secrets |
| 产物 | `Playra-build` artifact 120,090,605 B → `Playra_android.apk` 89,610,711 B |
| APK sha256 | `4c944f690525a12b33e6b23705ccdd3d1cb325e3ccd42dbda70ab5c80048705e` |
| 版本 | `com.predidit.kazumi` versionName `2.4.2` / versionCode `20402` |
| 签名 | `CN=Playra, OU=Local Build, O=Playra`，证书 sha256 `1e974a5a…64649f44`（release key，非 debug） |
| 内嵌 SDK | `inputs.json`: `sdkCommit=d3d7d93`, `integrationVersion=3` |

### 5.2 内嵌资产完整性（`unzip` 后逐文件 sha256 与清单比对）

| APK 内路径 | 结果 |
|---|---|
| `lib/arm64-v8a/liblumafuse.so` | OK `31485cd8…` |
| `lib/x86_64/liblumafuse.so` | OK `fefdd5da…` |
| `lib/arm64-v8a/liblumina_core_vendor.so` | OK `26727c7b…` |
| `assets/flutter_assets/assets/lumina_private/fuse_image.bin.gz` | OK `184b5c35…` |
| `assets/flutter_assets/assets/lumina_private/profile.json` | OK `1247afd6…` |

5/5 与 `inputs.json` 一致 —— CI 注入的私有输入就是本地验证过的那一份，没有串包。

### 5.3 真机 UI 走查（Honor LLD-AL20 / arm64-v8a / Android 9 / Magisk root）

安装用 CI 产物覆盖安装 2.3.8 失败（`INSTALL_FAILED_UPDATE_INCOMPATIBLE`，签名不同），
先用 root 备份应用数据（`/sdcard/playra-data-backup.tgz`，15,419,856 B，
sha256 `dcd33bea…f9c6`），卸载后安装 2.4.2。

实测链路（截图存 `playra-local/frida/`，本仓库不入库）：

1. 引导页 → 首页：真实 Lumina 目录（精选推荐「药屋少女的呢喃 第三季」、推荐·日漫、推荐·国漫）；
2. 首卡进入详情：`播放设置 动漫·Lumina`、线路 3、画质 自动/4K/1080p、选集 5 集；
3. 起播成功：视频画面 + 字幕「魔女无法说谎」+「上次看到 第1集 · 0:02」，
   播放设置行显示 **`3840×2160 · 实际分辨率`**（4K 直链探针生效）。

即：目录/详情/播放/取流四条链路在正式 APK 内可用，不是只有 host 侧能跑。

### 5.4 host 七操作（同一份代码，`dart run bin/live.dart`）

| 操作 | 结果 | ms |
|---|---|---|
| config | pass | 350 |
| channels | pass | 250 |
| banners | pass | 476 |
| catalog | pass | 623 |
| search | pass | 189 |
| detail | pass | 198 |
| play | pass | 2748（mediaProbe: HTTP 206 / 6944 B / mp4=true） |

## 6. 与原 App 同口径速度对比（2026-11-03）

### 6.1 测量口径

- 同一台设备（`37KRX18825013759`）、同一个 frida 脚本 `frida/measure_v2.js`、
  同一次冷启动式旅程（首页 → 首卡详情 → 起播）。对照 App：囧次元 `1.5.8.0`（versionCode 88）。
- 计时点是引擎调用本身：在 `libcore.so` / `liblumina_core_vendor.so` 的 `call` 导出上
  `Date.now()` 取差值，**不含 Dart 侧 JSON 解析与 HTTP**；输入长度在调用返回后扫描
  （避开把字符串扫描算进耗时）。
- 两个包的引擎库是同一份供应商库（Playra 侧改名为 `liblumina_core_vendor.so`，
  sha256 与本仓库交付的 `libcore_android_arm64.so` 一致），因此差异只剩宿主侧调用方式。

### 6.2 结果

| 指标 | 囧次元 App | Playra 2.4.2 APK | 说明 |
|---|---|---|---|
| 解密调用次数 | 118 | 8 | App 更"碎"：大量 556 B 小包 |
| 解密总耗时 | 17,590 ms | 8,159 ms | 同一次用户旅程 |
| 中位耗时 | 38 ms | 415 ms | 分布不同，中位不可直接比 |
| 最大耗时 | 5,480 ms | 5,590 ms | 均在冷启首调 |
| 输入密文总量 | 289.1 KB | 117.0 KB | — |
| 归一化吞吐 | 60.84 ms/KB | 69.71 ms/KB | Playra 慢 14.6% |
| 冷启首调 | 5,470 / 5,480 ms @576 / 664 B | 5,590 ms @5,312 B | 引擎初始化 + 标定，两宿主同现象 |
| 稳态 21–27 KiB | 421 / 457 / 468 ms | 514 / 625 / 693 ms | Playra 1.22–1.48× |

分层看（原始逐调用记录折算成 ms/KiB，只取 ≥16 KiB 的大包）：

| 宿主 | 样本（载荷 KiB → ms = ms/KiB） |
|---|---|
| 囧次元 App | 19.4→185=9.5、20.2→196=9.7、33.6→395=11.7、18.2→351=19.3、21.8→421=19.3、24.7→457=18.5、26.0→468=18.0、17.2→398=23.1 |
| Playra 2.4.2 | 16.0→315=19.7、21.2→514=24.3、25.8→625=24.2、25.5→693=27.2 |

- App 呈**双峰**：~9.5–11.7 ms/KiB 的快档 3 笔，~18.0–23.1 ms/KiB 的慢档 5 笔；
- Playra 只有单峰 19.7–27.2 ms/KiB —— 慢档与 App 慢档重叠，**没有快档**。

快档成因未定，最可能是同会话内重复 K 命中已有标定（[HYP]，见 §6.4 验证动作）。
两者都不含首次冷启那笔 5.5 s。

### 6.3 结论

1. **单次解密吞吐两边同量级**（60.8 vs 69.7 ms/KB，差 15%）；Playra 没有"引擎变慢"的结构性问题。
2. **整段旅程的解密总耗时 Playra 更低**（8.2 s vs 17.6 s），原因不是更快，而是**调用次数与载荷量更少**
   （8 次 / 117 KB vs 118 次 / 289 KB）——Playra 的目录接口按页取，App 一次拉全。
3. **冷启动 ~5.5 s 是共同现象**（引擎初始化 + 首包标定），不属于 Playra 特有回归；
   首屏体感应扣除这一笔再比。
4. 稳态下同尺寸载荷（21–27 KiB）Playra 慢 1.2–1.5×；差距集中在"App 有快档、Playra 没有"。这是唯一需要继续追的差异。

### 6.4 差异归因（[HYP]，附验证动作）

- **[HYP] 调用契约不同**：抓到的入参形状两边不一致 —— Playra `call(a0,a1)` 的 `a1` 是 6 字节控制块
  （`01 7B …`），且 `a0` 前 24 字节跨 8 次调用完全固定（会话级头）；囧次元 `a1` 仅 1 字节、`a0` 每次不同。
  两者走的不是同一个入口/参数组合，逐字节不可等同。
  → 验证：把 `a1` 前 32 B 完整打印（`readHead(a[1],32)` 改为带 hex 输出），对照 `action` 语义。
- **[HYP] 宿主侧重复工作**：Playra 可能在 Dart 层对同一响应做两次解密（路由探测 + 正式解密）。
  本次未观测到 `lumafuse` 调用，暂不支持该假设。
  → 验证：同时挂 `lumafuse_decrypt`，统计每次 HTTP 响应触发的原生调用次数。
- **[HYP] 测量顺序偏差**：App 先跑、Playra 后跑，机身温度/CPU 调度可能系统性偏向后跑的 Playra。
  → 验证：交替顺序各跑 3 轮取中位（最便宜的证伪实验，建议先做）。

### 6.5 未采集项（NOT RUN）

- **Playra 的网络相**：本轮 `http` 事件为 0（`conns` 有 2，`req` 有累计，`resp` 无）。
  原因是 Flutter/Dart 在 Android 上读 socket 走 `read()`，而钩子集只有 `recv/recvfrom/__recvfrom_chk`；
  囧次元 App 走 `recv`，所以那边有 16 条 episode。
  → 下一命令：在 `measure_v2.js` 的接收钩子列表加入 `'read'`（`onEnter` 取 `fd/buf/len`，`onLeave` 取返回值），
  重跑同一旅程；成功判据是 Playra 侧 `http` 事件 ≥ 4 且 `resp > 0`。
- 两边的网络相（RTT/首字节）本次都不作为结论：App 侧 16 条 episode 有分片合并噪声，
  只用于确认"请求确实打到了 `43.145.33.254:27990`"。

## 7. 剩余限制

- 三个预存 UI 用例（`browse_auto_load` / `content_skeleton` / `modern_profile`）仍失败，
  已证与协议层无关（engine 三文件回退 A/B），CI 里不阻塞发布。
- core 加速后端只在上述一台 arm64 真机验证；x86_64 模拟器路径未跑。
- 速度对比是单轮测量，未做交替多轮；§6.4 三条假设都还没验证。
- Playra 侧网络相未采集（§6.5）。

## 8. 复现

```bash
# 私有输入（本机）
node tool/lumina-native-input.cjs verify
# 离线向量
cd packages/lumina_engine && dart run bin/check.dart <fixture.json> <profile.json> <image.bin>
# 真连七操作
cd packages/lumina_engine && dart run bin/live.dart <profile.json> <image.bin> <report.json>
```

设备侧测量（脚本在仓库外的 `playra-local/`，避免把私钥/日志带进公开仓）：

```bash
python measure_run.py --package com.predidit.kazumi --script frida/measure_v2.js \
    --out frida/pr_journey.jsonl --duration 120 --taps frida/taps_pr.json
```

本报告的逐调用数据（不含密文）见 `docs/analysis/measurements/lumina-speed-20261103.json`。
