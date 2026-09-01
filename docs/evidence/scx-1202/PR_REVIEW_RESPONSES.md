# SCX#1202 PR Review — Prepared Responses

For [sched-ext/scx#3780](https://github.com/sched-ext/scx/pull/3780). Paste into PR comments as needed.

## IND-SCX-001 — Reenqueue storm on every RT sched_switch

**Response:** The interceptor only calls `scx_bpf_reenqueue_local()` when `next` is SCHED_FIFO/RR/DEADLINE. We validated with `rt_guard_stress` 60s soak (no `SCX_EXIT_ERROR_STALL`). Happy to add a perf benchmark if reviewers want scale data.

Evidence: `RT_GUARD_PASS fail=0` — https://github.com/abdullahhanif-001/elite-ebpf-telemetry/blob/main/docs/evidence/scx-1202/VERIFICATION_20260901-045612/01-RT_GUARD_PASS.verdict

## IND-SCX-002 — partial-switch mode gap (Layer 2)

**Response:** Layer 3 is BPF-side preemption detection; Layer 2 watchdog patch (`scx_stall_caused_by_rt` in `ext.c`) handles full-mode RT mask and is submitted separately to LKML. Partial `SCX_OPS_SWITCH_PARTIAL` mode is explicitly out of scope for L3.

## IND-SCX-003 — CO-RE `next->policy` read

**Response:** Can switch to `BPF_CORE_READ` for `policy` if portability review requests it. Tested on 6.19-rc7 dirty kernel with CO-RE sched_ext build.

## bpfland integration

**Response:** Integration snippet in `contrib/rt_guard_stress/scx_bpfland_rt_guard_example.bpf.c`. Can add optional include to `scx_bpfland` in follow-up if preferred over header-only landing.

## Selftests location

**Response:** Kernel selftest sources are in `contrib/rt_guard_stress/` for copy into `tools/testing/selftests/sched_ext/`. Verified on VPS with patched Makefile (see evidence repo gates).

## If code changes requested

Re-run on sched_ext proof host:

```bash
export REAL_ONLY=1 ELITE_SRC=/opt/elite/src
bash scripts/contabo/run-scx-1202-evidence.sh
bash scripts/verify-scx-1202-evidence.sh
```

Commit new `VERIFICATION_*` bundle to evidence repo.
