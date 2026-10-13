# Playra 版本引用

2026-10-13 核对 origin 与 upstream：origin 的 129 个原始版本 tag 全部与官方同名对象一致，没有 Playra 自有版本 tag。tag 指向提交，不属于某条分支。

- 自有版本：`playra/v<版本>`，从 Playra main 的已验证提交创建。
- 官方源码：upstream 远端与本地 `kazumi-upstream` 分支；官方 tag 保存在本地 `upstream/<原版本>`。
- 精确清单：[official-tags.csv](official-tags.csv)。原 tag 对象已保存到本地引用和 `.dart_tool/release-branding-20261013/official-history.bundle`。
- 不向 origin 批量推送官方别名：旧提交的发布 workflow 接受所有 tag，可能触发大量旧版本构建。

用户确认后，已逐个校验对象 SHA，通过 atomic push 与精确 lease 删除清单中的 129 个 origin tag；再次查询远端 tag 数为 0。main、官方分支和 upstream 仓库保留。裸版本本地 tag 也已移至 upstream/*，后续 upstream fetch 使用独立 tag 映射，origin 自动跟随 tag 已关闭。

恢复某项引用：`git push origin refs/tags/upstream/<版本>:refs/tags/<版本>`。恢复旧 tag 可能触发旧发布流程，应先评估 Actions。Git bundle 可用 `git bundle verify` 校验，并在引用丢失时用于恢复对象。

未完成真机播放验证前不创建正式版本 tag 或 GitHub Release。代码推送与发布是独立操作。
