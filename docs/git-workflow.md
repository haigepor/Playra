# Playra Git 分支与官方更新

## 远程与分支职责

| 名称 | 来源或跟踪目标 | 用途 |
| --- | --- | --- |
| `origin` | `https://github.com/haigepor/Playra.git` | Playra 开发成果和分支的推送目标 |
| `upstream` | `https://github.com/Predidit/Kazumi.git` | 获取 Kazumi 官方更新 |
| `main` | `origin/main` | 当前本地项目的开发主线 |
| `kazumi-upstream` | `upstream/main` | 官方原版代码，只做快进同步；在 `origin` 保存同名分支 |

`main` 的默认拉取和推送都面向 `origin`。`kazumi-upstream` 拉取官方代码，推送到 Playra；不要在该分支提交定制功能，否则无法维持官方原版基线。

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
