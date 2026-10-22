# Upstream Maintainer Tracking

| Maintainer | Email | Layer | Status |
|------------|-------|-------|--------|
| Tejun Heo | tj@kernel.org | sched_ext tree | **Ready to submit** — pack in `scripts/server/submit-rt-guard-upstream.sh` |
| Andrea Righi | arighi@nvidia.com | ext_server (L1) | v12 in scx-dl-server; **rt_stall PASS** on test kernel |
| Peter Zijlstra | peterz@infradead.org | sched/core | Pending review |
| luigidematteis | GitHub #1202 | Reporter | Issue open — fix ready, PR #3780 to reopen |

## Proof (FULL bundle 2026-09-03)

| Gate | Result |
|------|--------|
| Kernel class | `6.19.0-rc7` + ftrace + sched_ext |
| Global eBPF D1–D6 | PASS |
| SCX1202 gate matrix H1–H12 | PASS (12/12) |
| RT Guard flood P1–P5 | PASS |
| Strict evidence verifier | `SCX1202_EVIDENCE_VERIFY=PASS` |

Published report: [`docs/GLOBAL_EBPF_VERIFICATION_REPORT.md`](../../docs/GLOBAL_EBPF_VERIFICATION_REPORT.md)  
Evidence: [`docs/evidence/scx-1202/VERIFICATION_20260903-012848/`](../../docs/evidence/scx-1202/VERIFICATION_20260903-012848/)

## Submission Artifacts

- Layer 2 patch: `contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch`
- Layer 3 BPF: `contrib/sched-ext/bpf/scx_rt_guard.bpf.h`
- Layer 3 selftest: `contrib/sched-ext/selftests/rt_guard_stress.{c,bpf.c}`
- LKML cover: `contrib/sched-ext/LKML_COVER_LETTER.txt`
- GitHub PR body: `contrib/sched-ext/GITHUB_PR_BODY.md`
- Reopen PR: [`docs/evidence/scx-1202/REOPEN_SCX_PR.md`](../../docs/evidence/scx-1202/REOPEN_SCX_PR.md)

## Next actions

1. **Reopen** [sched-ext/scx#3780](https://github.com/sched-ext/scx/pull/3780) and paste updated PR body (gates all green).
2. Comment on [#1202](https://github.com/sched-ext/scx/issues/1202) with evidence link + reopened PR link.
3. LKML Layer 2 — [`docs/evidence/scx-1202/LKML_SUBMISSION.md`](../../docs/evidence/scx-1202/LKML_SUBMISSION.md)

## References

- [sched-ext/scx#1202](https://github.com/sched-ext/scx/issues/1202)
- [sched-ext/scx#3780](https://github.com/sched-ext/scx/pull/3780)
- [LWN sched_ext overview](https://lwn.net/Articles/1055970/)
