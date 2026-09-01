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

## Test plan (verified on Contabo sched_ext kernel)

Evidence: [`docs/evidence/scx-1202/`](../../docs/evidence/scx-1202/) — run `bash scripts/verify-scx-1202-evidence.sh` from repo root.

- [x] rt_stall kselftest PASS — `VERIFICATION_*/01-RT_GUARD_PASS.verdict` (`RT_GUARD_PASS fail=0`)
- [x] rt_guard_stress 60s soak — same bundle (G3 in rt-guard-pass)
- [x] Issue #1202 repro `STALL_DETECTED=NO` — `VERIFICATION_*/02-HOLY_GRAIL.verdict` (H5)
- [x] PM2_GUARD_OK — see [GLOBAL_EBPF_VERIFICATION_REPORT.md](../../docs/GLOBAL_EBPF_VERIFICATION_REPORT.md) §Runtime Environment

Reproduce: [`docs/evidence/scx-1202/README.md`](../../docs/evidence/scx-1202/README.md)

Fixes sched-ext/scx#1202
