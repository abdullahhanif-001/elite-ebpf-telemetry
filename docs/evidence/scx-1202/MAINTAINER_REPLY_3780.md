# Maintainer reply — sched-ext/scx#3780 (arighi)

**Question ([comment](https://github.com/sched-ext/scx/pull/3780#issuecomment-5489538680)):**  
Why do we need Layer 3 `scx_rt_guard`? Isn’t ext deadline server + `SCX_ENQ_IMMED` enough for RT stall (#1202)?

## Short answer

**Layer 1 (ext DL server) + `SCX_ENQ_IMMED` fix important enqueue/wakeup paths, but they do not replace a sched_switch-level guard for every BPF scheduler.** #1202 reproduces on production-style schedulers (e.g. `bpfland`) as **EXT runnable stall → watchdog eject**. Layer 3 is a **small, optional BPF header** that re-enqueues locally when RT/FIFO/RR/DEADLINE wins `sched_switch`, using `scx_bpf_reenqueue_local()` (kernel ≥ 6.19).

## Layering (what each piece does)

| Layer | Mechanism | What it fixes | What it does not fix |
|-------|-----------|---------------|----------------------|
| **L1** ext_server / DL | Kernel deadline server | RT vs EXT ordering in ext core | Schedulers that still leave EXT tasks not making forward progress on preemption edge cases covered in #1202 |
| **L2** RT-aware watchdog (kernel patch) | Skip false stall when RT monopolizes | Watchdog **false positive** eject | Does not run BPF scheduler enqueue logic on every RT preemption |
| **L3** `scx_rt_guard.bpf.h` | `sched_switch` → `scx_bpf_reenqueue_local()` on RT next | **BPF-side** forward progress when RT takes CPU | Not a replacement for L1/L2; defense-in-depth + reusable hook for custom schedulers |

`SCX_ENQ_IMMED` affects **how/when** tasks enter BPF paths; it does not implement the **sched_switch RT preemption hook** that #1202’s soak and matrix target.

## Evidence (fail-closed, no offline substitution for live claims)

**Committed FULL bundle** (audited on any machine):

```bash
git clone https://github.com/abdullahhanif-001/elite-ebpf-telemetry
cd elite-ebpf-telemetry
bash scripts/verify-scx-1202-evidence.sh          # SCX1202_EVIDENCE_VERIFY=PASS strict=1
bash scripts/verify-scx1202-matrix-from-bundle.sh
```

Bundle: [`VERIFICATION_20260903-012848`](./VERIFICATION_20260903-012848/) — captured on **`CONFIG_SCHED_CLASS_EXT=y`** host (`6.19.0-rc7-scx-dl`), not on generic 6.8 VPS.

| Gate | Verdict |
|------|---------|
| RT guard G0–G6 | `RT_GUARD_PASS fail=0` (no `LOADER=SKIP` on sched_ext host) |
| kselftest | `rt_stall` + `rt_guard_stress` 60s soak PASS |
| #1202 repro | `STALL_DETECTED=NO` with `LOADER=bpfland` |
| Matrix | `SCX1202_MATRIX_PASS=YES checks=12/12` |
| Flood | `RT_GUARD_FLOOD_PASS fail=0` |

**Live re-run** (requires sched_ext kernel): `REAL_ONLY=1 bash scripts/server/run-scx-1202-evidence.sh`

## Limitations (documented)

- **LIMIT-SCX-001:** 60s soak / matrix — not fleet-scale perf proof.
- **LIMIT-SCX-002:** L2 partial-switch / FAIR-only hogging — separate from #1202 RT monopolization class.

## Ask

Review Layer 3 as **optional** `scx_rt_guard.bpf.h` + kselftest `rt_guard_stress` (same pattern as scx_qmap / 6.19+ API). Happy to fold into docs or gate behind compat if maintainers prefer a narrower scope.
