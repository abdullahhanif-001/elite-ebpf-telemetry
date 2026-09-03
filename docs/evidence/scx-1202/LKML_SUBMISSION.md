# Layer 2 LKML Submission — RT-Aware Watchdog (sched-ext/scx#1202)

**Status:** Ready to send (manual email — not automated)  
**Date prepared:** 2026-09-01

## Recipients

| To | Role |
|----|------|
| tj@kernel.org | sched_ext maintainer (Tejun Heo) |
| arighi@nvidia.com | ext_server author (Andrea Righi) |
| peterz@infradead.org | sched/core (Peter Zijlstra) |

**Cc:** sched-ext@lists.linux.dev

## Attachments

- Patch: [`contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch`](../../contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch)
- Cover letter: [`contrib/sched-ext/LKML_COVER_LETTER.txt`](../../contrib/sched-ext/LKML_COVER_LETTER.txt)

## Public evidence (link in email body — do not attach raw VPS logs)

```text
Evidence: https://github.com/abdullahhanif-001/elite-ebpf-telemetry/blob/main/docs/evidence/scx-1202/VERIFICATION_20260901-045612/01-RT_GUARD_PASS.verdict
Verifier: https://github.com/abdullahhanif-001/elite-ebpf-telemetry/blob/main/scripts/verify-scx-1202-evidence.sh
Layer 3 PR: https://github.com/sched-ext/scx/pull/3780
```

## Send command

```bash
git send-email \
  --to tj@kernel.org \
  --to arighi@nvidia.com \
  --to peterz@infradead.org \
  --cc sched-ext@lists.linux.dev \
  --subject "[PATCH] sched_ext: RT-aware watchdog stall detection (sched-ext/scx#1202)" \
  contrib/sched-ext/LKML_COVER_LETTER.txt \
  contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch
```

Or send manually from your email client with patch attached and cover letter as body.

## Email body addition (paste after cover letter)

```text
Verified on production server (kernel 6.19.0-rc7, CONFIG_SCHED_CLASS_EXT=y):
  RT_GUARD_PASS fail=0
  rt_stall + rt_guard_stress kselftests PASS

Public evidence: https://github.com/abdullahhanif-001/elite-ebpf-telemetry/tree/main/docs/evidence/scx-1202
Layer 3 BPF header PR: https://github.com/sched-ext/scx/pull/3780
Issue: https://github.com/sched-ext/scx/issues/1202
```

## After sending

1. Record LKML message-id in [UPSTREAM_PR_TRACKER.md](UPSTREAM_PR_TRACKER.md)
2. Link thread from #1202 comment if applicable
