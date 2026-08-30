# sched_ext: Add scx_rt_guard RT preemption interceptor (fixes #1202)

## Summary

- Adds reusable `scx_rt_guard.bpf.h` — sched_switch tracepoint interceptor
- Calls `scx_bpf_reenqueue_local()` when next task is SCHED_FIFO/RR/DEADLINE
- Complements ext_server (kernel Layer 1) and RT-aware watchdog (Layer 2)

### Motivation

sched-ext/scx#1202 — RT tasks monopolize CPU → EXT tasks stall → watchdog
ejects BPF scheduler. Layer 3 provides BPF-side preemption detection using
the pattern from scx_qmap (kernel >= 6.19, a3f5d48).

### Files

- `tools/sched_ext/include/scx/scx_rt_guard.bpf.h`
- `tools/testing/selftests/sched_ext/rt_guard_stress.c`
- `tools/testing/selftests/sched_ext/rt_guard_stress.bpf.c`

### Test plan

- [x] rt_stall kselftest PASS (EXT >= 4% under RT load)
- [x] rt_guard_stress 60s soak — zero SCX_EXIT_ERROR_STALL
- [x] Issue #1202 repro — no runnable task stall after fix
- [x] PM2_GUARD_OK on Contabo VPS (5 co-resident apps)

Fixes sched-ext/scx#1202
