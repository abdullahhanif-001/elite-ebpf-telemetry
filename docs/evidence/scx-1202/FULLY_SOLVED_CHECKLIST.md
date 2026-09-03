# SCX#1202 — Post-Merge Checklist (fully solved)

Run these steps **after** [sched-ext/scx#3780](https://github.com/sched-ext/scx/pull/3780) merges.

## 1. Confirm upstream merge

```bash
gh pr view 3780 --repo sched-ext/scx --json state,mergedAt,mergeCommit
```

## 2. Close or confirm #1202 closed

GitHub should auto-close via `Fixes #1202`. If not:

```bash
gh issue close 1202 --repo sched-ext/scx --comment "Fixed by sched-ext/scx#3780"
```

## 3. Fresh evidence run on server

```bash
ssh production-server 'bash /opt/elite/src/scripts/server/run-scx-1202-evidence.sh'
```

Copy new `VERIFICATION_*` bundle to repo; update `MANIFEST.json` with upstream merge commit SHA.

## 4. Update documentation

| File | Change |
|------|--------|
| [`README.md`](../../README.md) | "verified fix" → "resolved upstream (scx#3780, YYYY-MM-DD)" |
| [`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md) | Mark upstream PR merged |
| [`UPSTREAM_PR_TRACKER.md`](UPSTREAM_PR_TRACKER.md) | Check all boxes |

## 5. Google / portfolio update

- Resume/LinkedIn: "Co-authored sched_ext RT-guard fix (sched-ext/scx#1202, PR #3780)"
- Use [`GOOGLE_VERIFICATION_BRIEF.md`](GOOGLE_VERIFICATION_BRIEF.md) with updated upstream status

## Current status (2026-09-01)

- Layer 3 PR **OPEN** — awaiting maintainer merge
- Layer 2 LKML — ready, email pending
- Issue #1202 — **OPEN**
- Claim: **verified fix** (not fully solved until steps above complete)
