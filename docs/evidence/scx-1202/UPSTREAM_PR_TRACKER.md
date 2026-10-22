# SCX#1202 Upstream PR Tracker

**Last updated:** 2026-09-03

## Layer 3 — sched-ext/scx (BPF interceptor)

| Field | Value |
|-------|-------|
| PR | ~~#3780~~ **CLOSED** (withdrawn for dev — reopen when ready) |
| Status | **Development in progress** — not ready for maintainer review |
| Fixes | [#1202](https://github.com/sched-ext/scx/issues/1202) |
| Issue comment | [issuecomment-5489342030](https://github.com/sched-ext/scx/issues/1202#issuecomment-5489342030) |

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

- [x] Layer 3 PR opened on sched-ext/scx (later withdrawn for dev)
- [x] Comment on #1202 with evidence links
- [ ] LKML email sent (Layer 2)
- [ ] PR reopened and merged
- [ ] Issue #1202 closed
