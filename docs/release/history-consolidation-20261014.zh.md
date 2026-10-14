# 2026-10-14 提交历史精简与恢复记录

## 范围与授权

用户在分支整理完成后要求精简提交历史，确认按推荐的 7 个主题执行。改写对象只有 Playra `main`，使用绑定整理前远程 SHA 的 `--force-with-lease` 推送，不使用无条件 `--force`。

- 早期历史边界：`24e04806bc9abdb67eca8bf197d66dc44fb49f0c`，该提交及其全部祖先保留。
- 整理前主线：`264dbb212a5f597ec2341c1c5228a3ac66e4ff08`，本轮范围共 23 条提交。
- 官方镜像：`025dcb5c2f62db881382c72f191d08b49a9feb41`，本轮不移动、不重写。
- 整理后：本轮范围改为 7 条单父主题提交，不增加长期分支或公共备份标签。

## 主题与文件树映射

| 主题 | 原提交数 | 原分组末端 | 新主题提交 |
|---|---:|---|---|
| 四类内容与并发聚合搜索 | 7 | `dac19b50` | `a83d20a2` |
| 影视播放器与 iOS 新版页面 | 2 | `ed0a36df` | `eb3fd352` |
| iOS、桌面云构建与验证 | 8 | `1bc1e847` | `5e412417` |
| 安卓键盘与播放缓冲反馈 | 3 | `74a0441a` | `5910c248` |
| 页面样式与响应式布局 | 1 | `a8fddbcb` | `a4abd2ac` |
| SDK 播放源与自动画质选线 | 1 | `5fba8b5b` | `2f412a9d` |
| 接入规范、归档与历史维护 | 1 | `264dbb21` | 包含本文的最后一条主题提交，使用 `git log -1` 查看 |

前 6 条新提交的完整文件树分别等于原分组末端，不是重新按补丁猜测合并结果。各主题提交正文保留对应原提交完整 SHA 与原说明，用于追溯。第 7 条额外更新 `docs/git-workflow.md` 并新增本文；除此以外，最终所有跟踪文件与原主线完全一致。

既有自动化和构建对应的应用文件没有变化，本轮使用 Git 对象及文件树比较验证，没有因提交 ID 改变而重跑全部平台测试。旧安装包收据中的原源码 SHA 不被伪造更新；查看源码时使用上述映射或原始备份。

## 原提交覆盖范围

- 搜索：`70845b1c`、`ee31a8bc`、`8ef82ae9`、`3b135a25`、`91694535`、`e27b9046`、`dac19b50`。
- 影视与 iOS 页面：`a474b579`、`ed0a36df`。
- 云构建：`1d1c86f6`、`2aab0930`、`844baab7`、`c08e72e7`、`d4ac701e`、`1591ced2`、`8f400996`、`1bc1e847`。
- 安卓体验：`10f60e39`、`43cee1c0`、`74a0441a`。
- 样式：`a8fddbcb`。
- SDK：`5fba8b5b`。
- 文档：`264dbb21`。

这批原提交的变更都保留在对应的新主题文件树中；旧提交不再位于新主线的祖先链，不能继续以“旧提交是 main 祖先”作为核验方式，应比较映射与文件树。

## 本机恢复材料

位置：`.git/codex-backups/history-cleanup-20261014/`。不提交、不推送到公共仓库，也不会随正常克隆传递。

| 材料 | 用途 |
|---|---|
| `before.bundle` | 整理前 main 与官方镜像的完整历史，已执行 bundle verify |
| `plan.json` | 原分组、完整提交列表、文件树、新主题 SHA 与范围约束 |
| `refs.before.txt`、`status.before.txt`、`config.before`、`index.before` | 原引用、工作区、Git 配置与索引快照 |
| `recipes.before.json`、`submodule.before.patch` | 原有本地辅助文件与播放器子模块状态 |
| `result.json` | 实际远程推送结果、最终 SHA 和核验结果 |

只读查看备份中的引用：

```powershell
git bundle list-heads .git/codex-backups/history-cleanup-20261014/before.bundle
```

确需恢复旧历史时，先从备份提取到临时恢复分支检查，不直接覆盖正在开发的主线：

```powershell
git fetch .git/codex-backups/history-cleanup-20261014/before.bundle refs/heads/main:refs/heads/restore-main-before-history
git diff main restore-main-before-history -- lib test android web tool
```

恢复远程属于另一次历史更新：先读取当前远程提交、保存更新后的成果，再明确授权并使用对应租约；不要复用本轮旧租约或无条件强推。临时恢复分支完成用途后删除，正常保留分支仍为 `main`、`kazumi-upstream`。

## 其他克隆与历史图

其他设备应先 `git fetch origin --prune --no-tags --no-recurse-submodules`，保存本地独有提交及未提交内容，再按实际情况对齐新主线；普通 `git pull` 可能把旧开发链重新合回来。重新克隆也是可选方式，但私有 SDK、工具链与本地数据需自行保留。

图形客户端刷新引用后，新主线只显示本轮 7 个主题；选择同时显示官方分支时仍有两条历史线，这是保留官方原版与 Playra 定制的预期结果。旧 reflog、缓存或本地恢复材料可能仍可看到原提交，不应通过清空 reflog、删除备份或改写官方历史来隐藏它们。
