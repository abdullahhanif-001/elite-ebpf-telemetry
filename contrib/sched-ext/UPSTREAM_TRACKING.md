# Upstream Maintainer Tracking

| Maintainer | Email | Layer | Status |
|------------|-------|-------|--------|
| Tejun Heo | tj@kernel.org | sched_ext tree | Pending LKML submission |
| Andrea Righi | arighi@nvidia.com | ext_server (L1) | v12 reviewed; in scx-dl-server branch |
| Peter Zijlstra | peterz@infradead.org | sched/core | Pending review |
| luigidematteis | GitHub #1202 | Reporter | Issue open |

## Submission Artifacts

- Layer 2 patch: `contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch`
- Layer 2 live on VPS: `apply-rt-watchdog-patch.sh` applied to `/opt/scx-kernel-build/kernel/sched/ext.c`
- Layer 3 BPF: `contrib/sched-ext/bpf/scx_rt_guard.bpf.h`
- Layer 3 selftest: `contrib/sched-ext/selftests/rt_guard_stress.c`
- LKML cover: `contrib/sched-ext/LKML_COVER_LETTER.txt`
- GitHub PR body: `contrib/sched-ext/GITHUB_PR_BODY.md`

## VPS Proof (pending kernel reboot)

Target verdict: `scripts/oneclick/results/rt-guard-*/verdict.txt` → `RT_GUARD_PASS fail=0`

## References

- [sched-ext/scx#1202](https://github.com/sched-ext/scx/issues/1202)
- [LWN sched_ext overview](https://lwn.net/Articles/1055970/)
- `git://git.kernel.org/pub/scm/linux/kernel/git/arighi/linux.git scx-dl-server`
