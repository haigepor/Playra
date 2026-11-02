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

## 5. 已知限制 / 待办

- Android 真机/模拟器安装 APK 后的七操作与播放验收（本次 CI 出包后补）。
- 与原生 App 的同口径速度对比（需区分直连/代理，并扣除 frida RPC 基线）。
- core 加速后端（arm64 供应商 `libcore`）需真机验证；本次本地只覆盖 fuse 路径。
- 三个预存 UI 用例待单独修。

## 6. 复现

```bash
# 私有输入（本机）
node tool/lumina-native-input.cjs verify
# 离线向量
cd packages/lumina_engine && dart run bin/check.dart <fixture.json> <profile.json> <image.bin>
# 真连七操作
cd packages/lumina_engine && dart run bin/live.dart <profile.json> <image.bin> <report.json>
```
