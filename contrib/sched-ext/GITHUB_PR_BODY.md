# sched_ext: Add scx_rt_guard RT preemption interceptor (draft for sched-ext/scx)

## Summary

- Adds reusable `scx_rt_guard.bpf.h` — sched_switch tracepoint interceptor
- Calls `scx_bpf_reenqueue_local()` when next task is SCHED_FIFO/RR/DEADLINE
- Complements ext_server (kernel Layer 1) and RT-aware watchdog (Layer 2)

## Motivation

sched-ext/scx#1202 — RT tasks monopolize CPU → EXT tasks stall → watchdog
ejects BPF scheduler. Layer 3 provides BPF-side preemption detection using
the pattern from scx_qmap (kernel >= 6.19, a3f5d48).

## Files

- `tools/sched_ext/include/scx/scx_rt_guard.bpf.h`
- `tools/testing/selftests/sched_ext/rt_guard_stress.c`
- `tools/testing/selftests/sched_ext/rt_guard_stress.bpf.c`

## Test plan (must pass before upstream PR)

Evidence: [`docs/evidence/scx-1202/`](../../docs/evidence/scx-1202/) — run `bash scripts/verify-scx-1202-evidence.sh` from repo root.

- [ ] `RT_GUARD_PASS fail=0` on sched_ext kernel (G0–G6, no SKIP when sched_ext enabled)
- [ ] `rt_stall` kselftest PASS
- [ ] `rt_guard_stress` 60s soak PASS
- [ ] Issue #1202 repro `STALL_DETECTED=NO` with `LOADER=bpfland` (not SKIP)
- [ ] `scx_loader` built and on PATH for G6 soak

**Status:** Development in progress. Previous PR #3780 withdrawn. Issue #1202 remains open until full gate matrix passes on DO VPS (`143.244.164.216`).

Reproduce: [`docs/evidence/scx-1202/README.md`](../../docs/evidence/scx-1202/README.md)

Related: sched-ext/scx#1202 (not yet closed)
