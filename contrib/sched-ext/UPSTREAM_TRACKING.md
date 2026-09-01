# Upstream Maintainer Tracking

| Maintainer | Email | Layer | Status |
|------------|-------|-------|--------|
| Tejun Heo | tj@kernel.org | sched_ext tree | **Ready to submit** — pack in `scripts/contabo/submit-rt-guard-upstream.sh` |
| Andrea Righi | arighi@nvidia.com | ext_server (L1) | v12 in scx-dl-server; **rt_stall PASS** on VPS test kernel |
| Peter Zijlstra | peterz@infradead.org | sched/core | Pending review |
| luigidematteis | GitHub #1202 | Reporter | Issue open |

## VPS Proof (2026-08-31)

| Gate | Result |
|------|--------|
| Kernel | `6.19.0-rc7` + ftrace + sched_ext |
| Global eBPF D1–D6 | PASS |
| Holy Grail H1–H12 | PASS (12/12) |
| RT Guard flood P1–P5 | PASS |
| Verdict | `GLOBAL_EBPF_PASS fail=0` |

Published report: [`docs/GLOBAL_EBPF_VERIFICATION_REPORT.md`](../../docs/GLOBAL_EBPF_VERIFICATION_REPORT.md)  
sched_ext evidence: [`contrib/sched-ext/EVIDENCE_REPORT.md`](EVIDENCE_REPORT.md)

## Submission Artifacts

- Layer 2 patch: `contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch`
- Layer 2 live on VPS: `scripts/contabo/apply-rt-watchdog-patch.sh` → `scx_stall_caused_by_rt()` in `ext.c`
- Layer 3 BPF: `contrib/sched-ext/bpf/scx_rt_guard.bpf.h`
- Layer 3 selftest: `contrib/sched-ext/selftests/rt_guard_stress.{c,bpf.c}`
- LKML cover: `contrib/sched-ext/LKML_COVER_LETTER.txt`
- GitHub PR body: `contrib/sched-ext/GITHUB_PR_BODY.md`
- Submission pack generator: `scripts/contabo/submit-rt-guard-upstream.sh`

## Next Actions

1. Monitor [sched-ext/scx#3780](https://github.com/sched-ext/scx/pull/3780) — Layer 3 BPF header PR
2. Send Layer 2 LKML patch — [`docs/evidence/scx-1202/LKML_SUBMISSION.md`](../../docs/evidence/scx-1202/LKML_SUBMISSION.md)
3. Address PR review — [`docs/evidence/scx-1202/PR_REVIEW_RESPONSES.md`](../../docs/evidence/scx-1202/PR_REVIEW_RESPONSES.md)
4. After merge: [`docs/evidence/scx-1202/FULLY_SOLVED_CHECKLIST.md`](../../docs/evidence/scx-1202/FULLY_SOLVED_CHECKLIST.md)

## References

- [sched-ext/scx#1202](https://github.com/sched-ext/scx/issues/1202)
- [LWN sched_ext overview](https://lwn.net/Articles/1055970/)
- `git://git.kernel.org/pub/scm/linux/kernel/git/arighi/linux.git scx-dl-server`
