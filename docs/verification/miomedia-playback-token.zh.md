# MioMedia 播放凭证接入验收

核验日期：2026-10-12。项目：`C:/Users/haige/Desktop/Playra`。

## 实现与边界

已同步提供方 `C:/Users/haige/Desktop/instruct/tv-reverse-api/sdk/python/miomedia/`。
12 个 SDK 文件中，10 个字节完全一致；`profile.py/config.py` 只保留项目既有 TODO 注释，环境绑定值与提供方相同。`suite/block/signature/device/transport` 与二进制表均未修改。版本与 SHA-256 清单见 `tool/source_runtime/vendor/sdk-manifest.json`。

依据提供方 `docs/api/ads.md`「换取额度与凭证」和 `docs/api/playback.md`，桥接允许 SDK 调用固定槽位的 `ad/getConfig` 和供给任务的 `ad/claimReward`，由 SDK 为每集取得新 nonce、凭证并提交 `adToken`。不缓存或下发凭证，不开放任意奖励请求，不增加广告事件或观看时长上报。

应用使用持久身份，因此显式 `STRATEGY_TOKEN`；不再传兼容参数 `rotate_on_ad`。SDK 原有 AUTO 与 ROTATE 策略完整保留，用于独立诊断；没有在项目内重复实现身份重置或重试循环。凭证仍失败时保留 `ad_required`，不会自动清空应用设备态。

`ad/claimReward` 与 `resolve/exchange` 的响应丢失不自动重提，避免重复消费 nonce 或令牌。既有超时、取消、输入校验、媒体地址校验与公开错误码保留。`caps=[]`；作品 ID 为字符串。

`GET /v1/adapters` 的 `playbackHealth` 仅含策略、累计重置次数、播放尝试次数与最终 `ad_required` 次数；计数作用域为服务进程，重启归零。播放结果增加 `strategy/rotated/rotations`，原有 `status/media/selection` 不变。密钥、nonce、adToken 和 SDK 内部错误文本不返回客户端。

## 直接验证结果

| 检查 | 结果 |
|---|---|
| vendored SDK，目录内 `python selftest.py` | ALL PASS，PLAYBACK 12/12 |
| vendored SDK，`python -m miomedia.selftest` | ALL PASS，PLAYBACK 12/12 |
| 提供方原脚本 `e2e_playback_adtoken.py --episodes 5` | 5/5 ready，重置 0 次 |
| 提供方原脚本 `--episodes 4 --strategy rotate` | 4/4 ready，重置 4 次 |
| vendored SDK AUTO，5 集逐集检查媒体 | PASS，身份保留，重置 0 次 |
| vendored SDK ROTATE，4 集逐集检查媒体 | PASS，重置 4 次 |
| 应用 `MioMediaSdk` TOKEN，3 集与服务实例重建 | PASS，身份不变，重置 0 次 |
| 实际 Dart HTTP 客户端＋独立 Python 服务＋独立 Node Web 桥接 | 23 项 PASS，包括两条路径各连续播放 2 集、身份与输出边界 |
| Python runtime 回归 | 27 项 PASS |
| Node Web 桥接回归 | 5 项 PASS |

全部联调使用新建隔离测试身份，未运行当前应用的身份维护命令。对照中的第 1 集实际返回 MP4：HTTP 200、`video/mp4`、`ftyp` 容器头；其余集 HTTP 200、`application/vnd.apple.mpegurl`、`#EXTM3U`。同时验证 MIME 与文件头，HTTP 200 的 HTML 页不会被判为媒体。

脱敏逐集结果位于 `.dart_tool/miomedia-token-before-20261012/{auto,rotate,bridge}.json`。握手严格比较派生密钥，仅输出是否一致，不记录密钥值。

## 可复现命令

在项目根目录执行：

```powershell
python -X utf8 -m unittest discover -s tool/source_runtime -p 'test_*.py'
node --test tool/web_backend/runtime.test.cjs
python -X utf8 tool/source_runtime/miomedia_playback_check.py --episodes 5 --report .dart_tool/miomedia-token-before-20261012/auto.json
python -X utf8 tool/source_runtime/miomedia_playback_check.py --episodes 4 --strategy rotate --report .dart_tool/miomedia-token-before-20261012/rotate.json
python -X utf8 tool/source_runtime/miomedia_playback_check.py --episodes 3 --strategy token --bridge --report .dart_tool/miomedia-token-before-20261012/bridge.json
.\.tooling\flutter\bin\cache\dart-sdk\bin\dart.exe --packages=.dart_tool/package_config.json tool/miomedia_runtime_integration.dart C:/Users/haige/AppData/Local/Programs/Python/Python313/python.exe
```

`dart run` 触发项目已有 media_kit 原生构建钩子，在本机 Visual Studio 检测时出现 `FormatException: Control character in string`。该检查脚本仅依赖 Dart HTTP 客户端，直接以 Dart VM 和现有 package_config 运行完成 23 项检查；未修改 Visual Studio 或项目原生工具链。

## 当前运行服务与生效限制

当前 8945 服务仍是原来运行的进程。自动审批拒绝停止并重启该服务的命令，返回 `blocked by policy`；该命令未执行，当前应用身份文件未被替换。独立服务验收已验证新代码，但当前预览的旧服务不能据此声明已经启用凭证。

需要在原来的服务终端停止服务，再使用相同 `PLAYRA_MIOMEDIA_STATE_DIR` 启动，以保留原设备身份：

```powershell
python -B -X utf8 tool/source_runtime/server.py --port 8945
```

不要删除 `device.json`、不要运行 `miomedia_identity.py --replace`。服务就绪后，访问 `/v1/adapters`，MioMedia 应包含 `playbackHealth.strategy=token`。Android 沿用现有外部 HTTP 服务桥接，本轮没有重新打包 APK；真实 Android 设备的画面、音频与切集仍需设备测试。

## 修改文件与回滚

| 文件 | 用途／影响 |
|---|---|
| `tool/source_runtime/vendor/miomedia/__init__.py` | 导出新策略与凭证能力 |
| `tool/source_runtime/vendor/miomedia/playback.py` | 原样同步提供方播放高层编排，12 项自检 |
| `tool/source_runtime/vendor/sdk-manifest.json` | 更新版本与完整性清单 |
| `tool/source_runtime/miomedia_adapter.py` | 固定凭证端点、TOKEN 策略、消费请求禁止自动重提、脱敏监测 |
| `tool/source_runtime/test_miomedia_content.py` | 新 nonce、连续播放、4031 保持身份、消费请求不重提与媒体验证回归 |
| `tool/source_runtime/test_miomedia.py` | HTTP 暴露脱敏监测且不触发身份初始化 |
| `tool/source_runtime/miomedia_playback_check.py` | 新建隔离策略／媒体联调脚本 |
| `tool/miomedia_runtime_integration.dart` | 隔离服务身份，新增原生与 Web 播放契约验收 |
| `docs/miomedia-content-playback.zh.md` | 更新应用策略与监测说明 |
| 本文 | 记录证据、限制与回滚位置 |

原 Python runtime 副本与工作区状态位于 `.dart_tool/miomedia-token-before-20261012/source_runtime/` 和 `git-status.txt`；原 Dart 验收脚本副本同目录。文档 `miomedia-content-playback.zh.md` 的原内容按本轮三处明确变更还原并保存于同目录。回滚只恢复表中的变更文件，移除本轮新脚本与本文；不覆盖既有用户改动，不操作设备身份文件。SDK 其余 10 个文件内容没有业务变化。

范围外：骨架屏、页面布局、规则算法与密码学实现。本轮未修改这些内容。外部平台正式绑定值仍待确认，当前为默认值联调。
