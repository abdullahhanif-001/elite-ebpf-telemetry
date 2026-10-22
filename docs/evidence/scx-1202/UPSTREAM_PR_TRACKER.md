# SCX#1202 Upstream PR Tracker

**Last updated:** 2026-09-03  
**Layer 3 fix:** **READY** — full gates green; reopen upstream PR.

## Layer 3 — sched-ext/scx (BPF interceptor)

| Field | Value |
|-------|-------|
| PR | [#3780](https://github.com/sched-ext/scx/pull/3780) — **CLOSED (dev pause only)** → **reopen now** |
| Status | **Ready for maintainer review** — dev complete (`VERIFICATION_20260903-012848`, `status=FULL`) |
| Fixes | [#1202](https://github.com/sched-ext/scx/issues/1202) |
| PR body | [`contrib/sched-ext/GITHUB_PR_BODY.md`](../../contrib/sched-ext/GITHUB_PR_BODY.md) |
| Reopen steps | [`REOPEN_SCX_PR.md`](REOPEN_SCX_PR.md) |

## Layer 2 — LKML (watchdog patch)

| Field | Value |
|-------|-------|
| Patch | [`contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch`](../../contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch) |
| Instructions | [LKML_SUBMISSION.md](LKML_SUBMISSION.md) |
| Status | **READY — email not yet sent** |
| LKML message-id | _(fill after send)_ |

## Layer 1 — ext_server (track only)

| Field | Value |
|-------|-------|
| Author | Andrea Righi |
| Branch | `arighi/linux` `scx-dl-server` |
| Action | Monitor mainline merge — do not re-submit |

## Evidence repo

| Field | Value |
|-------|-------|
| Bundle | [VERIFICATION_20260903-012848](VERIFICATION_20260903-012848/) (`status=FULL`) |
| Verifier | `bash scripts/verify-scx-1202-evidence.sh` · offline: `bash scripts/verify-elite-offline.sh` |

## Upstream checklist

- [x] Layer 3 implementation + selftests in repo
- [x] Full gate matrix 12/12 + flood PASS (committed evidence)
- [x] Strict static verifier PASS
- [x] PR #3780 opened (closed temporarily for dev — **reopen**)
- [ ] PR #3780 **reopened** on sched-ext/scx (maintainer review)
- [ ] Comment on #1202 with fresh evidence link (after reopen)
- [ ] LKML email sent (Layer 2)
- [ ] PR merged → issue #1202 closed upstream
