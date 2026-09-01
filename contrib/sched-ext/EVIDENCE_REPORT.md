# sched_ext RT Monopolization — Evidence Report

**Status:** Verified on Contabo VPS (4 vCPU, 8 GB RAM), 2026-08-31  
**Issue:** [sched-ext/scx#1202](https://github.com/sched-ext/scx/issues/1202) — RT monopolization / runnable task stall  
**Full report:** [`docs/GLOBAL_EBPF_VERIFICATION_REPORT.md`](../../docs/GLOBAL_EBPF_VERIFICATION_REPORT.md)

---

## Summary

| Gate | Result |
|------|--------|
| RT Guard flood (P1–P5) | PASS |
| Holy Grail H1–H12 | PASS (12/12) |
| kselftest `rt_stall` | EXT ≥4% under RT load (symptom reproduced) |
| kselftest `rt_guard_stress` | 60s soak — no stall exit |
| #1202 repro with bpfland | `STALL_DETECTED=NO` |
| Negative control (`enq_last`) | PASS |
| 30-minute bpfland endurance | PASS |

---

## Kernel & Scheduler Coverage

- **Kernel:** `6.19.0-rc7` with `CONFIG_SCHED_CLASS_EXT=y`, ftrace enabled
- **Layer 2:** RT-aware watchdog patch in `ext.c` (live on VPS)
- **Layer 3:** `scx_rt_guard.bpf.h` + `rt_guard_stress` selftest
- **Schedulers tested:** bpfland, rusty, flash, rustland, layered (PASS_LOADER); lavd (SKIP — BPF arena)

---

## Artifacts in Repository

| Path | Description |
|------|-------------|
| `contrib/sched-ext/kernel/0001-sched_ext-rt-aware-watchdog.patch` | Layer 2 upstream patch |
| `contrib/sched-ext/bpf/scx_rt_guard.bpf.h` | Layer 3 BPF header |
| `contrib/sched-ext/selftests/rt_guard_stress.{c,bpf.c}` | kselftest harness |
| `benchmarks/sched-ext-gates/` | Flood-safe gate scripts (P1–P7) |
| `benchmarks/ebpf-gates/holy-grail-verify.sh` | H1–H12 matrix verifier |

Raw VPS logs are kept locally under `scripts/oneclick/results/` (gitignored). Use the verification scripts above to regenerate evidence on a sched_ext host.

---

## Upstream Next Steps

See [`UPSTREAM_TRACKING.md`](UPSTREAM_TRACKING.md) for maintainer contacts and submission commands (`scripts/contabo/submit-rt-guard-upstream.sh`).
