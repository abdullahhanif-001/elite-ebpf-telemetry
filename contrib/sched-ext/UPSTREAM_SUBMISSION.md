# Upstream Submission Pack — RT Monopolization Fix

## Layer 1: ext_server (Andrea Righi — track separately)

- **Branch:** `git://git.kernel.org/pub/scm/linux/kernel/git/arighi/linux.git scx-dl-server`
- **Status:** v12 reviewed; Peter Zijlstra approved merge (Feb 2026)
- **Action:** Monitor LKML; VPS test kernel built from this branch via `sched-ext-vps-prep.sh`
- **Do not re-submit** — carry branch on test VPS only until mainline merge

## Layer 2: RT-Aware Watchdog (submit to sched_ext tree)

**Patch:** [`kernel/0001-sched_ext-rt-aware-watchdog.patch`](kernel/0001-sched_ext-rt-aware-watchdog.patch)

**To:** Tejun Heo <tj@kernel.org>, Andrea Righi <arighi@nvidia.com>, Peter Zijlstra <peterz@infradead.org>

**Subject:** `[PATCH] sched_ext: RT-aware watchdog stall detection (sched-ext/scx#1202)`

**Cover letter summary:**

> When RT tasks monopolize CPUs, SCHED_EXT runnable tasks stall and the
> watchdog ejects the BPF scheduler with SCX_EXIT_ERROR_STALL — a false
> positive documented in sched-ext/scx#1202. This patch skips stall detection
> when (a) per-CPU kthreads are starved by RT on the same CPU, or (b) in
> full switch mode, all CPUs in p->cpus_ptr have rt_nr_running > 0.
> Partial switch mode is excluded.

**Test plan:**

- `tools/testing/selftests/sched_ext/rt_stall` PASS (ext_server required)
- `rt_guard_stress` 60s soak PASS
- Issue #1202 repro: no SCX_EXIT_ERROR_STALL

## Layer 3: scx_rt_guard BPF Interceptor (PR to sched-ext/scx)

**Files:**

- `bpf/scx_rt_guard.bpf.h` — reusable sched_switch interceptor
- Integration example: add to `scheds/c/scx_bpfland` via `#include <scx/scx_rt_guard.bpf.h>`

**PR title:** `sched_ext: Add scx_rt_guard RT preemption interceptor (fixes #1202)`

**PR body:**

```markdown
## Summary
- Adds reusable `scx_rt_guard.bpf.h` using sched_switch + scx_bpf_reenqueue_local()
- Detects SCHED_FIFO/RR/DEADLINE preemption and re-enqueues local DSQ tasks
- Complements ext_server (Layer 1) and RT-aware watchdog (Layer 2)

## Test plan
- [ ] rt_stall kselftest PASS
- [ ] rt_guard_stress 60s soak PASS
- [ ] scx_bpfland under RT load — no watchdog exit

Fixes sched-ext/scx#1202
```

## Maintainer Tracking

| Maintainer | Role | Contact |
|------------|------|---------|
| Tejun Heo | sched_ext maintainer | tj@kernel.org |
| Andrea Righi | ext_server author | arighi@nvidia.com |
| Peter Zijlstra | sched/core | peterz@infradead.org |
| luigidematteis | #1202 reporter | GitHub #1202 |

## VPS Evidence Artifacts

After `rt-guard-pass.sh`:

- `scripts/oneclick/results/rt-guard-YYYYMMDD/verdict.txt` → `RT_GUARD_PASS fail=0`
- Attach to LKML cover letter and scx PR

## Submission Checklist

- [ ] VPS kernel >= 6.19 with CONFIG_SCHED_CLASS_EXT=y
- [ ] arighi scx-dl-server branch (ext_server)
- [ ] Layer 2 patch applied and kernel rebuilt
- [ ] rt_stall PASS (EXT >= 4% runtime)
- [ ] rt_guard_stress PASS (60s soak)
- [ ] rt-monopolization-repro.sh → STALL_DETECTED=NO
- [ ] PM2_GUARD_OK (5 neighbor apps unchanged)
- [ ] Email Layer 2 to LKML / sched_ext list
- [ ] Open Layer 3 PR on github.com/sched-ext/scx
