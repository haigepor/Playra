# Playra Git 分支与官方更新

## 远程与分支职责

| 名称 | 来源或跟踪目标 | 用途 |
| --- | --- | --- |
| `origin` | `https://github.com/haigepor/Playra.git` | Playra 开发成果和分支的推送目标 |
| `upstream` | `https://github.com/Predidit/Kazumi.git` | 获取 Kazumi 官方更新 |
| `main` | `origin/main` | 当前本地项目的开发主线 |
| `kazumi-upstream` | `upstream/main` | 官方原版代码，只做快进同步；在 `origin` 保存同名分支 |

`main` 的默认拉取和推送都面向 `origin`。`kazumi-upstream` 拉取官方代码，推送到 Playra；不要在该分支提交定制功能，否则无法维持官方原版基线。

## 2026-10-14 提交历史精简

完成分支归并后，用户明确授权把本轮 23 条开发提交整理为 7 条中文主题提交。整理范围仅为 `24e04806` 之后、原 `264dbb21` 之前的这批开发历史；此前历史、共同祖先和官方分支均保持不变。原 SDK 功能提交 `5fba8b5b` 的完整文件树对应整理后的 `2f412a9d`。

前 6 个主题逐一保留各原分组末端的完整文件树；第 7 个主题保留原文档归档，并补充本节及[提交映射与恢复记录](release/history-consolidation-20261014.zh.md)。应用代码、测试、依赖、工作流和构建输入没有改变。本次历史重写只针对 `main`，推送使用绑定原远程提交的 `--force-with-lease`；如果远程已变化则停止，不覆盖其他人的新提交。

这次是用户确认后的专项历史整理，不改变日常优先快进推送的规则。其他设备仍指向旧历史时，应先保存未推送提交及工作区改动，再重新对齐 `origin/main`；不要普通合并旧 main，把已压缩的开发历史重新接回来。历史文档和旧构建收据中的原 SHA 保持原始含义，按映射查阅。

## 2026-10-14 首次主线归并与固定分支

本地和 `origin` 长期只保留 `main`、`kazumi-upstream`。日常 Playra 开发归入 `main`；如果确实需要临时隔离分支，完成合并与远程核验后删除，不再长期保留 `codex/*` 开发分支。

首次归并时核对发现 `codex/content-search-20261013` 的 `ed0a36df` 已完整包含在 `codex/platform-builds-20261014` 的 `5fba8b5b` 中。`main` 的 `24e04806` 也是后者祖先，因此先以 `--ff-only` 把 22 条功能提交完整纳入主线，当时没有压缩、重建或丢弃历史，没有代码冲突。测试与构建对应的功能文件树保持一致；归档文档另作提交。随后经用户授权进行的提交精简见上一节。

官方镜像从本地 `2768c230`、远程 `4960f9c0` 快进到实际抓取的官方 `025dcb5c`（官方版本 2.3.9）。这只更新 `kazumi-upstream`，不表示 Playra `main` 已升级到官方 2.3.9；新的官方功能仍需单独评估、合并和回归。两个分支不要求文件树相同。

日常分支清理顺序固定为：保存本地恢复点 → 核对所有分支独有提交 → 合并到 main → 验证 → 普通快进推送 main 与官方镜像 → 读取远程确认 → 删除已合并临时分支 → 再核对分支清单。未经明确授权，禁止用强制推送、`reset --hard` 或删除尚未纳入主线的分支来“整理”。不会向 `upstream` 官方仓库推送。

本次恢复点位于 `.git/codex-backups/branch-consolidation-20261014/`：

- `before.bundle`：已验证的 Git 历史包，包含整理前各分支引用；备份不显示为额外分支，也不推送到远程。
- `refs.before.txt`、`status.before.txt`、`config.before`：原分支、工作区与 Git 配置记录。
- `worktree/`：原有未跟踪文件副本。
- `libmpv.before.patch`：原有播放器子模块的修改快照。

五份原有分析文档作为带日期的历史记录归档到[分析导航](analysis/README.md)，不能把旧设计状态当作当前功能事实。空的本地 `recipes.json` 和播放器子模块内原有状态保留本地，不作为应用代码提交、发布或重置。

日后需要恢复被删的开发分支时，可先检查 `git bundle list-heads .git/codex-backups/branch-consolidation-20261014/before.bundle`，再从指定引用提取到临时恢复分支核对；不要直接覆盖主线。备份只保存在本机 `.git`，不会随正常克隆传递。

## 2026-10-10 整理依据

整理前本地 `main` 跟踪 Kazumi，Playra 远程名为 `playra`。远程 Playra 骨架与本地主线没有共同祖先，也不是同一套目录布局。

补齐官方历史后，确认本地基线 `caf7185` 与官方 `2.3.8` 提交 `11671bc` 的文件树相同；本地 `3d453a4` 与官方 `2768c23` 的文件树也相同，说明截至该官方提交的三个修复已包含在本地代码中，只是提交哈希不同。

主线从官方 `2768c23` 延伸，以一条 Playra 定制提交承载当前已提交的项目代码和本说明。保留完整官方历史，移除重复的本地历史和仅用于连接历史的合并提交。此前独立骨架不再混入主线；备份、归档分支及备份标签按用户要求删除。

```text
官方历史 ── 2768c23 ── 后续官方更新       kazumi-upstream
                  └── Playra 定制与后续开发  main
```

两条分支保留共同祖先，便于普通合并；职责分别是官方原版和 Playra 定制。后续官方更新不能使用 `ours` 策略，否则会丢弃新功能和修复。

## 2026-10-11 新克隆核验

工作区 `D:/project/Playra` 是完整克隆，并非浅克隆。远程 `origin/main` 为 `072d7e67`，`origin/kazumi-upstream` 和官方 `upstream/main` 均为 `2768c230`。分支间提交数量是官方独有 0 条、Playra 独有 2 条；两次定制提交均为单父提交，没有在该范围产生合并提交。

```text
官方历史（1930 条可达提交）── 2768c230  upstream/main、kazumi-upstream、origin/kazumi-upstream
                              └── adce00db ── 072d7e67  main、origin/main
```

图形界面把祖先与后代画在同一条线上是正常现象：两个分支是两个提交指针，不等于必须立即出现两条岔开的线。官方出现新提交后，在同步分支快进更新而 main 尚未集成时，图形就会自然分叉。官方分支本身没有包含 Playra 定制代码。

用户已确认保留共同祖先。新克隆已补齐 `upstream` 和本地 `kazumi-upstream`，仅获取官方 main；`main` 跟踪 `origin/main`，`kazumi-upstream` 跟踪 `upstream/main`。仓库默认推送远程与两条本地分支的 `pushRemote` 均为 `origin`，不会默认向官方仓库推送。本次未重写历史或推送远程。

核验与查看：

```powershell
git branch -vv
git remote -v
git rev-list --left-right --count upstream/main...origin/kazumi-upstream
git log --oneline kazumi-upstream..main
git log --graph --decorate --oneline main kazumi-upstream upstream/main -20
```

本次变更前的 Git 配置和全部 refs 历史位于 `.git/codex-backups/git-organization-20261011/config.before` 与 `before.bundle`。bundle 是历史备份，不覆盖工作区，也不在正常分支列表显示；恢复配置前先确认后续是否有新增设置。2026-10-10 文档中的旧机器备份与 reflog 不随新克隆传递，不能在此工作区据此承诺恢复更早的定制小提交。

2026-10-10 整理时，原有 `.gitignore`、`MERGE_REPORT.md`、`recipes.json` 和 `fastlane/.libmpv-android-video-build` 子模块内的改动曾留在旧工作区；这不是 2026-10-11 新克隆的当前状态。切换分支前，应以实时 `git status` 保存工作区改动；子模块内的改动需要在子模块中单独处理。

## 同步官方分支

以下命令在仓库根目录、工作区已妥善保存后执行。官方历史发生重写时，`--ff-only` 会拒绝更新，应先检查原因。

```powershell
git fetch upstream --no-tags --no-recurse-submodules
git switch kazumi-upstream
git merge --ff-only upstream/main
git push origin kazumi-upstream
git switch main
```

检查新增官方提交与累计代码差异：

```powershell
git log --oneline main..kazumi-upstream
git diff --stat main kazumi-upstream
git diff main kazumi-upstream -- lib pubspec.yaml
```

`git diff main kazumi-upstream` 会同时体现 Playra 自有修改和官方差异。只查看共同祖先之后官方一侧新增的改动：

```powershell
git diff main...kazumi-upstream
```

## 集成官方更新

先在临时集成分支普通合并、处理冲突和验证，再合入主线。将示例中的日期替换为实际日期，并确保分支名尚未存在。

```powershell
git switch main
git pull --ff-only origin main
git switch -c codex/kazumi-update-YYYYMMDD
git merge --no-ff kazumi-upstream
# 处理冲突，检查改动，完成针对性测试和目标平台验证。
git switch main
git merge --ff-only codex/kazumi-update-YYYYMMDD
git push origin main
# 核实临时分支已经包含在 origin/main 后再清理；仅推送过才删除远程同名分支。
git merge-base --is-ancestor codex/kazumi-update-YYYYMMDD origin/main
git branch -d codex/kazumi-update-YYYYMMDD
# 若曾推送：git push origin --delete codex/kazumi-update-YYYYMMDD
```

合并尚未完成且决定放弃本次集成时，在工作区无其他新增改动的前提下可执行 `git merge --abort`。后续更新不要使用强制推送，也不要对官方同步分支直接开发。

## 历史查看与恢复

只查看 Playra 自有提交：

```powershell
git log --oneline kazumi-upstream..main
git log --graph --oneline --decorate main kazumi-upstream
```

SourceTree 选择 `main` 或 `kazumi-upstream` 分别查看对应主线；共同祖先以下是官方历史。旧的重复历史不会再由备份分支或备份标签引用。

本次整理通过保留文件树的提交重建实现，没有重置或覆盖工作区。历史重建前的本地提交可在 `git reflog main` 查看；原 Git 配置与状态核验记录位于 `.git/codex-backups/git-organization-20261010-225013/`，不出现在分支列表，也不提交到仓库。reflog 有保留期限，不能作为永久备份。后续若需恢复，应先从旧提交建立临时分支核对，避免覆盖后续开发。
