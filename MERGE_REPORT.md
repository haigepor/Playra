# 分支合并结果报告

**日期**：2026-10-10
**仓库**：Kazumi（Flutter 3.47.6 / Dart 3.13.5），工作区 `C:/Users/haige/Desktop/Playra`
**结论**：`main` 已合并 `codex/windows-build-validation`，冲突 1 处已按证据解决；`origin/m3e-player` 未合并（见遗留风险）。

---

## 一、合并的提交范围

### 合并前基线对齐

| 项 | 合并前 | 合并后 |
|---|---|---|
| 本地 `main` | `11671bc` version 2.3.8（**落后 origin/main 3 个提交**） | `3a4b61c` |
| `origin/main` | `2768c23` | 已快进到 `2768c23` |

先执行快进同步，纳入上游 3 个提交：

- `7b19c30` fix(video_side_panel): remove left safe inset from video side panel (#2640)
- `4e821e4` fix(download): rebase iOS download paths after container relocation (#2626)
- `2768c23` feat(download): support android custom directories (#2647)

### 被合并分支：`codex/windows-build-validation`（2 个提交）

- `ca151db` fix: preserve complete ECH certificate bundle on Windows
  —— 引入 `third_party/ech_http/` 本地副本（修复 MSVC C2026 证书字符串编译限制），新增 CA bundle 原生测试。
- `14203b8` fixt：重新设计安卓首页
  —— 新增 `lib/presentation/` 现代 UI 体系（modern home / shadcn 组件画廊 / 平台适配层），
  并将 `lib/services/`、`lib/request/` 大量模块拆分为 `_native.dart` / `_web.dart` 条件导入结构。

### 本次产生的提交

| 提交 | 说明 | 规模 |
|---|---|---|
| `eef7769` | Merge branch 'codex/windows-build-validation' into main | 315 文件，+26608 / −1194 |
| `2dab42b` | style: apply dart format（仅对合并涉及文件） | 62 文件，+3613 / −2854 |
| `c8b6157` | chore: 删除会话验证产物与 7 篇一次性分析文档 | 45 文件，−4904 |
| `3a4b61c` | docs: README 补充本地 `ech_http` 覆盖说明 | 1 文件 |

---

## 二、冲突及处理方式

**冲突总数：1 处**（其余 6 个重叠文件由 git 自动合并成功）。

### `lib/services/platform/secure_bookmark_service.dart`（modify / delete）

- **上游（HEAD）**：`2768c23` 删除该文件（原 60 行）。
- **codex 分支**：修改该文件，仅 1 处 import 重构：`dart:io` → `package:kazumi/services/platform/platform_io.dart`。

**判据（非盲选任一方）**：

1. 上游删除的原因是功能迁移而非弃用 —— 新增的 `lib/services/download/download_directory_service.dart`
   已完整接管 `SecureBookmarks`、`resolveBookmark`、`startAccessingSecurityScopedResource`
   以及 `SettingsKeys.downloadDirectoryBookmark` 的读写。
2. codex 侧改动是平台拆分重构的顺带 import 替换，**不含任何功能变更**。
3. 删除后全树 `grep` 无任何 `secure_bookmark_service` / `SecureBookmarkService` 引用。

**处理**：采纳上游删除（`git rm`）。保留该文件会形成一个功能重复、无人引用的死实现。

---

## 三、验证情况

### ✅ 已执行

| 校验项 | 结果 |
|---|---|
| 冲突标记残留扫描（`lib/`、`test/`） | 无残留 |
| 全量 import/export/part 解析（534 个 dart 文件 / 2646 条指令） | **0 个无法解析** |
| 重复 import 扫描（合并后 `lib/` 全量） | 0 个文件存在重复 import |
| `dart format` 合规检查（合并涉及的 204 个 dart 文件） | 62 个不合规，已统一格式化并提交 |

### ❌ 未执行（环境硬限制）

`flutter analyze` / `flutter test` / 任何构建 **均无法在本环境运行**。

原因：**Dart 运行时无法创建子进程** —— 任何 `Process.start` 都失败：

```
CreateFile failed 231
ProcessException: 所有的管道范例都在使用中。 (process_win.cc:744)
```

已排除的因素：

- 与 git 二进制无关（PortableGit 与 Git for Windows 均失败）。
- 与沙箱无关（关闭沙箱后仍失败）。
- **与进程生成能力无关**：Python 可正常 `subprocess.run(['git','--version'])`，Dart 不可。
  即这是 Dart 运行时在本环境的专有缺陷，会阻断 flutter 工具链全部子命令。

**请在正常环境中补跑以下命令以完成验证**：

```bash
export PATH="/c/Users/haige/Desktop/Playra/.tooling/flutter/bin:$PATH"
flutter pub get
flutter analyze            # 期望 0 error
flutter test               # 期望全绿
```

---

## 四、整理收尾内容

- **分支**：`codex/windows-build-validation` 与临时备份分支 `backup/pre-merge-20261010` 均已删除；
  两者提交已全部可从 `main` 到达，删除不丢失任何提交（reflog 仍可找回）。
- **文件**：删除 `docs/verification/`（154 个文件 / 14MB）。其中 38 个已入库（截图 PNG、JSON 探测记录），
  116 个 `.log` 因上游 `.gitignore` 的 `*.log` 规则本就未入库。
- **文档**：连带删除引用上述产物的 7 篇一次性分析文档（`kazumi-analysis.md`、`android-ui-skeleton.md`、
  `platform-dependency-readiness.md`、`shadcn-ui-integration.md`、`web-android-port.md`、
  `visual-studio-setup-analysis.md`、`modern-home-redesign.md`），避免留下失效引用。
- **未跟踪文件**：删除 `recipes.json`（空 recipes 数组 + 时间戳，工具生成残留）。
- **代码风格**：`dart format` 统一 62 个合并涉及文件（未触碰其他既有代码）。
- **说明更新**：README「开发」章节新增「本地依赖覆盖」小节，说明 `ech_http` 被覆盖到 `third_party/ech_http` 的原因。

---

## 五、遗留风险

1. **未做编译/测试验证（中风险）**
   静态校验只能证明结构完整，无法证明类型正确与运行时行为正确。
   新增的 `lib/presentation/`（约 900 行 `modern_home_view.dart`）、shadcn 画廊、
   以及 `_native.dart`/`_web.dart` 条件导入拆分均未经过 `flutter analyze` / `flutter test`。

2. **`origin/m3e-player` 悬而未决（高风险，如后续要合并）**
   - 上游长期分支，1863 个提交，tip 为 `494e20f draft`，**基于 v2.3.1 时期**，而 main 已是 v2.3.8。
   - 与本次合并内容**重叠 42 个文件**，集中在 `lib/pages/menu/menu.dart`、
     `lib/request/core/bangumi_transport.dart`、`lib/services/network/system_proxy_service.dart` 等。
   - **本地是浅克隆（depth=1）**，与 `m3e-player` **无公共祖先**，直接 merge 会被拒绝；
     合并前必须先 `git fetch --unshallow`（或至少 deepen 到公共祖先）。

3. **本地 `main` 仍落后上游（低风险）**
   `main` 现在领先 `origin/main` 5 个提交（3 个上游提交 + 本次 4 个提交中的 3 个祖先关系），
   但未推送。上游若继续推进，建议尽早同步以免再次落后。

4. **`ech_http` 本地覆盖会随上游漂移（低风险）**
   `dependency_overrides` 把 `ech_http` 锁定到 `third_party/ech_http`。
   上游发布 0.2.2+ 后需重新评估：要么把补丁提给上游，要么在升级时重新打补丁。

5. **submodule 仍为 dirty（低风险，非本次引入）**
   `fastlane/.libmpv-android-video-build` 显示 `(modified content)`，
   是合并前就存在的状态，本次未改动。

---

## 六、后续建议

1. **优先补跑验证**：在正常环境执行 `flutter pub get && flutter analyze && flutter test`，
   重点看 `lib/presentation/` 与条件导入模块的类型错误。
2. **决定是否处理 `m3e-player`**：
   - 若不需要，建议直接忽略（它是上游维护者的开发分支，落后主线 7 个版本）。
   - 若需要，先 `git fetch --unshallow origin`，再用 `git merge-base` 定位真实分叉点，
     **不要**用 `--allow-unrelated-histories` 强行合并。
3. **取消浅克隆限制**：`git fetch --unshallow origin`，并把 fetch refspec 改为
   `+refs/heads/*:refs/remotes/origin/*`，避免以后再漏掉远程分支。
4. **推送前同步**：`git fetch origin && git rebase origin/main`（或 merge）后再 push，
   降低与上游的偏离。
5. **考虑把 `docs/verification/` 这类产物加入 `.gitignore`**，避免会话型验证输出再次入库。
