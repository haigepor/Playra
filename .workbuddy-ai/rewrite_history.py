"""Rewrite the shallow-grafted 10-commit lineage of `main` into a self-contained
history, so it can be pushed to a remote that does not accept shallow updates.

Only the grafted root's dangling parent pointer is dropped; every commit keeps its
original tree, message, author, committer and timestamps. Merge topology is preserved.
"""
import os
import subprocess
import sys

REPO = r"C:\Users\haige\Desktop\Playra"


def git(*args, input=None, env=None):
    return subprocess.run(
        ["git", *args],
        cwd=REPO,
        input=input,
        capture_output=True,
        text=True,
        encoding="utf-8",
        env=env,
    )


order = git("rev-list", "--topo-order", "--reverse", "main").stdout.split()
if not order:
    print("no commits found")
    sys.exit(1)

mapping = {}
for old in order:
    line = git("rev-list", "--parents", "-n", "1", old).stdout.strip().split()
    parents_old = line[1:]
    # Only keep parents we have already rewritten; this drops the grafted parent.
    new_parents = [mapping[p] for p in parents_old if p in mapping]

    tree = git("rev-parse", old + "^{tree}").stdout.strip()
    fmt = "%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI"
    meta = git("show", "-s", "--format=" + fmt, old).stdout.strip("\n").split("\x00")
    if len(meta) != 6:
        print("metadata parse failed for", old, meta)
        sys.exit(1)
    an, ae, ad, cn, ce, cd = meta
    msg = git("show", "-s", "--format=%B", old).stdout

    env = dict(os.environ)
    env.update(
        {
            "GIT_AUTHOR_NAME": an,
            "GIT_AUTHOR_EMAIL": ae,
            "GIT_AUTHOR_DATE": ad,
            "GIT_COMMITTER_NAME": cn,
            "GIT_COMMITTER_EMAIL": ce,
            "GIT_COMMITTER_DATE": cd,
        }
    )

    args = ["commit-tree", tree]
    for p in new_parents:
        args += ["-p", p]
    res = git(*args, input=msg, env=env)
    if res.returncode != 0:
        print("commit-tree failed for", old, res.stderr)
        sys.exit(1)

    mapping[old] = res.stdout.strip()
    dropped = [p for p in parents_old if p not in mapping]
    print(
        f"{old[:8]} -> {mapping[old][:8]}  parents={[p[:8] for p in new_parents]}"
        + (f"  dropped={[p[:8] for p in dropped]}" if dropped else "")
    )

new_head = mapping[order[-1]]
print("NEW_HEAD", new_head)
with open(os.path.join(REPO, ".workbuddy-ai", "new_head.txt"), "w") as fh:
    fh.write(new_head)
