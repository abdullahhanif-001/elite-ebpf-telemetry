# Reopen sched-ext/scx PR #3780 (fix ready)

Dev pause is over. Gates are **FULL** (`VERIFICATION_20260903-012848`). Reopen the Layer 3 PR for review.

## 1. Reopen the PR

1. Open [sched-ext/scx pull #3780](https://github.com/sched-ext/scx/pull/3780).
2. Click **Reopen pull request** (author: @abdullahhanif-001).
3. Replace the PR description with [`contrib/sched-ext/GITHUB_PR_BODY.md`](../../contrib/sched-ext/GITHUB_PR_BODY.md) (all test-plan boxes checked).

## 2. Comment on issue #1202

Post on [sched-ext/scx#1202](https://github.com/sched-ext/scx/issues/1202):

```text
Update: Layer 3 fix is ready for review — full gate matrix 12/12, STALL_DETECTED=NO with bpfland, RT_GUARD_FLOOD_PASS.

Committed evidence (strict verifier PASS):
https://github.com/abdullahhanif-001/elite-ebpf-telemetry/tree/main/docs/evidence/scx-1202/VERIFICATION_20260903-012848

Reopened PR: https://github.com/sched-ext/scx/pull/3780
```

## 3. Optional — submission pack

```bash
bash scripts/server/submit-rt-guard-upstream.sh
```

## Verify before commenting

```bash
bash scripts/verify-elite-offline.sh
# or
bash scripts/verify-scx-1202-evidence.sh
```
