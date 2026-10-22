# sched_ext: Add scx_rt_guard RT preemption interceptor (fixes #1202)

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

## Test plan (FULL evidence — 2026-09-03)

Evidence: [`abdullahhanif-001/elite-ebpf-telemetry` `docs/evidence/scx-1202/VERIFICATION_20260903-012848/`](https://github.com/abdullahhanif-001/elite-ebpf-telemetry/tree/main/docs/evidence/scx-1202/VERIFICATION_20260903-012848) — auditors: `bash scripts/verify-scx-1202-evidence.sh` (strict PASS).

- [x] `RT_GUARD_PASS fail=0` on sched_ext kernel (G0–G6, no SKIP when sched_ext enabled)
- [x] `rt_stall` kselftest PASS
- [x] `rt_guard_stress` 60s soak PASS
- [x] Issue #1202 repro `STALL_DETECTED=NO` with `LOADER=bpfland` (not SKIP)
- [x] `scx_loader` built and on PATH for G6 soak
- [x] SCX1202 matrix H1–H12 — `SCX1202_MATRIX_PASS=YES checks=12/12`
- [x] `RT_GUARD_FLOOD_PASS fail=0`

**Status:** **Fix ready for review.** PR [#3780](https://github.com/sched-ext/scx/pull/3780) was closed temporarily while dev finished (scx_loader + full gate matrix). **Please reopen #3780** for maintainer review — gates are green; this body is current.

Reproduce: [`docs/evidence/scx-1202/README.md`](https://github.com/abdullahhanif-001/elite-ebpf-telemetry/blob/main/docs/evidence/scx-1202/README.md)

Fixes sched-ext/scx#1202
