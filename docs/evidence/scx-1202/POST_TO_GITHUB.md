# Manual GitHub actions (abdullahhanif-001 token)

Cloud agent `gh` integration **cannot** comment on `sched-ext/scx` or fork `cilium/tetragon`. Run locally:

## 1. PR #3780 — reply to arighi

```bash
gh pr comment 3780 --repo sched-ext/scx \
  --body-file docs/evidence/scx-1202/MAINTAINER_REPLY_3780.md
```

Optional — refresh PR body:

```bash
gh pr edit 3780 --repo sched-ext/scx --body-file contrib/sched-ext/GITHUB_PR_BODY.md
```

## 2. Issue #1202 — status comment

Link bundle + #3780 + maintainer reply doc.

## 3. Tetragon PR

Follow [`contrib/tetragon/README.md`](../../contrib/tetragon/README.md).
