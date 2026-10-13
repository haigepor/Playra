# Playra 品牌与发布整理验证记录

日期：2026-10-13

## 交付内容

- 应用可见名称统一为 Playra；正式构建隐藏组件实验室和诊断日志入口，保留本地错误日志供开发诊断。
- 关于页改为 Playra 品牌介绍、使用帮助、隐私说明和二级许可与致谢入口。
- 更新检查只接受 Playra 自有稳定版本；底层安装标识、数据路径和通信接口保持升级兼容。
- Android 内置 Python 内容 SDK 的私有输入与发布签名材料由本地忽略文件或 CI Secrets 提供，不提交 SDK 私密目录。
- 发布 workflow 只接受 `playra/v*`，只生成构建附件，不自动创建正式发布。
- origin 上 129 个同名官方 tag 已按确认范围删除；映射、本地 `upstream/*` 引用和 Git bundle 已保留，详见[tag 策略](../release/tag-policy.zh.md)。

## 验证结果

- Flutter 测试：528 项全部通过。
- Flutter analyze：退出码 0；0 个 error、0 个 warning，37 条 info lint。
- MioMedia SDK：模块目录和 `python -m miomedia.selftest` 均为 `SELFTEST ALL PASS`，playback 12/12。
- SDK 私有输入工具：4/4；内容接口脚本：44/44；Web runtime：5/5。
- Web release 构建通过，页面标题为 Playra；Web 后端依赖审计无漏洞。
- Android release APK 构建、签名校验、应用标签、ABI 和内置 SDK 自检均通过；APK 已安装并在 LDPlayer Android 14 x86_64 模拟器启动。
- UTF-8 检查、敏感值精确扫描和 `git diff --check` 均通过。

## 设备与发布边界

- 测试 APK：`build/releases/Playra-2.3.8-release-ui-20261013.apk`，SHA-256：`f835539920f4fcd9988ddba6b6ad6b02c09d5a1b7fd12c5e59e7a09f2b745a55`。
- 此 APK 使用与之前测试安装相同的调试证书，便于覆盖安装和保留数据；它不是正式签名版。
- 红米 K50 / Android 15 上的内容加载已恢复，但用户报告电影播放在数秒内失败并显示“暂时无法取得播放资源”。本轮没有在该手机上完成播放链路复现，因此仍需在新设备会话采集日志、核对线路和集数并定位失败阶段。
- 桌面 SDK 的单条直链 HTTP 200、旧 APK 的模拟器播放记录，都不能替代当前 APK 在红米真机上的播放验收。
- GitHub Actions 所需私有 SDK 输入和正式 Android 签名 Secrets 尚未配置或运行；本轮没有创建正式版本 tag 或 GitHub Release。

## 回滚与恢复

- 发布品牌 OpenSpec：`openspec/changes/prepare-playra-release/`。
- origin 官方 tag 映射与恢复说明：`docs/release/official-tags.csv`、`docs/release/tag-policy.zh.md`。
- 本机完整历史 bundle、原工作文件快照与逐文件备份保存在忽略目录 `.dart_tool/release-branding-20261013/`；该目录不推送。
- 提交后可用 `git revert <commit>` 按组回滚；恢复旧官方 tag 前需先评估其旧发布 workflow 是否会被触发。
