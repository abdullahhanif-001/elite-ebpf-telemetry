# SCX#1202 — Challenge Q&A Playbook

**Purpose:** Maps maintainer, reviewer, and auditor questions to reproduction commands and committed evidence paths.

**Canonical registry:** [TEST_BENCHMARK_REGISTRY.md](../../TEST_BENCHMARK_REGISTRY.md)

**Full suite:** `bash scripts/contabo/run-linux-ebpf-challenge-proof.sh`  
**Static verify (no VPS):** `bash scripts/verify-scx-1202-evidence.sh`

Evidence bundle: `docs/evidence/scx-1202/CHALLENGE_PROOF_<date>/`

---

## Quick verdict lines (copy-paste)

```bash
cat docs/evidence/scx-1202/CHALLENGE_PROOF_*/CHALLENGE_VERDICT.txt
# → LINUX_EBPF_CHALLENGE_PASS fail=0
```

---

## Q&A Matrix

| Who | Question (EN) | One command | Expected verdict | Evidence file |
|-----|---------------|-------------|------------------|---------------|
| **Andrea** | Is ext_server + SCX_ENQ_REIMED enough? | `bash benchmarks/sched-ext-gates/prove-scx1202-arighi.sh` | Arm C PASS, Arm B PASS | `tier2/ANDREA_PROOF_REPORT.md` |
| **Andrea** | Why scx_rt_guard on sched_switch? | Read mechanism in report | L3 calls `scx_bpf_reenqueue_local()` | `contrib/sched-ext/bpf/scx_rt_guard.bpf.h` |
| **Maintainer** | Does rt_stall pass? | `./runner rt_stall` in kselftests | `EXT task got 4.%` | `tier1/01-rt-guard-pass.log` or `tier2/arm-c-rt_stall.log` |
| **Maintainer** | Does rt_guard_stress 60s pass? | `./runner rt_guard_stress` | `60s soak with RT+EXT` | `tier1/01-rt-guard-pass.log` |
| **Auditor** | Is sched_ext enabled? | `grep CONFIG_SCHED_CLASS_EXT /boot/config-$(uname -r)` | `=y` | `00-preflight.txt` |
| **Auditor** | Valid proof host? | `hostname` + kernel check | sched_ext host, 6.19-rc7 | `00-preflight.txt` |
| **Auditor** | Full eBPF stack verified? | `bash benchmarks/ebpf-gates/global-ebpf-aggregate.sh` | `GLOBAL_EBPF_PASS fail=0` | `tier4/03-GLOBAL.verdict` |
| **Auditor** | H1–H12 matrix? | `bash benchmarks/ebpf-gates/holy-grail-verify.sh` | `HOLY_GRAIL_1202_SOLVED=YES checks=12/12` | `tier3/02-HOLY_GRAIL.verdict` |
| **Linus path** | Kernel patch needed? | Layer 2 watchdog + P2 negative control | RT-aware stall skip | `tier2/flood-P2.log` |
| **Skeptic** | False positive stall? | `rt-guard-negative-control.sh` | broken BPF still fails | `tier2/flood-P2.log` |
| **Skeptic** | REAL_ONLY enforced? | `bash benchmarks/ebpf-gates/ebpf-future-holes.sh` | FH10 PASS | `tier4/D6-future-holes.log` |
| **Product** | Telemetry probes work? | `bash benchmarks/ebpf-gates/telemetry-probe-gate.sh` | `TELEMETRY_PROBE_GATE_PASS` | `tier4/D3-telemetry.log` |
| **Product** | eBPF X-Ray live? | `bash scripts/oneclick/ebpf-xray-real-proof.sh` | `REAL_EBPF_XRAY_PASS` | `tier4/D4-xray.log` |
| **Scheduler** | All 6 loaders work? | `rt-guard-scheduler-matrix.sh` | 5/6 PASS_LOADER, lavd SKIP | `tier3/scheduler-matrix.json` |
| **#1202** | Stall still happens? | `rt-monopolization-repro.sh` | `STALL_DETECTED=NO` (fixed) | `tier1/02-repro.verdict` |
| **#1202** | 5min bpfland soak? | G6 in `rt-guard-pass.sh` | `SOAK_PASS` (no SKIP) | `tier1/01-rt-guard-pass.log` |
| **Flood** | P1-P5 all pass? | `rt-guard-flood-aggregate.sh` | `RT_GUARD_FLOOD_PASS fail=0` | `tier2/04-FLOOD.verdict` |

---

## Short answers

### Why is ext_server alone insufficient?

Layer 1 (ext_server) gives EXT tasks CPU time — `rt_stall` shows EXT ≥4% under RT load (Arm C). When RT monopolizes the CPU and the BPF scheduler lacks `scx_rt_guard`, the `sched_switch` path does not re-enqueue runnable EXT tasks. That gap is the core of #1202. Layer 3 (`scx_rt_guard`) closes it (Arm B).

### Is the full eBPF stack verified?

Yes — D1 inventory, D2 flood, D3 telemetry, D4 X-Ray, D5 Go tests, D6 future-holes. All aggregate to `GLOBAL_EBPF_PASS fail=0`.

### Why do SCX gates fail on generic cloud VPS images?

Kernels without `CONFIG_SCHED_CLASS_EXT` (e.g. stock 6.8 on some providers) cannot load sched_ext schedulers. SCX gates are valid only on a sched_ext proof host.

---

## Extended challenge (Tier 3b — optional ftrace day)

| Phase | Script | Notes |
|-------|--------|-------|
| P4b | `rt-guard-edge-matrix.sh` E1–E7 | Full edge matrix |
| P6/P7 | `rt-guard-endurance.sh` | 30min per scheduler |
| Boot | `boot-ftrace-kernel.sh` | Separate session |

Baseline `LINUX_EBPF_CHALLENGE_PASS` does not require Tier 3b.

---

## Reproduce commands

```bash
# Full challenge (sched_ext proof host, lite flood for 4vCPU/8GB)
export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_LITE_MODE=1
bash scripts/contabo/run-linux-ebpf-challenge-proof.sh

# Finish partial run (P5 lite + tier3/4)
bash scripts/contabo/run-challenge-finish-lite.sh

# Single tier
bash scripts/contabo/run-linux-ebpf-challenge-proof.sh 2

# VPS prep (first time)
bash scripts/contabo/sched-ext-vps-prep.sh scx-build
bash scripts/contabo/sched-ext-vps-prep.sh scx-loader
bash scripts/contabo/sched-ext-vps-prep.sh apply-patches
bash scripts/contabo/sched-ext-vps-prep.sh kselftest-build
bash scripts/contabo/sched-ext-vps-prep.sh verify

# Static verify (any machine)
bash scripts/verify-scx-1202-evidence.sh
```

---

## Maintainer reply template (#1202, @arighi)

> We agree ext_server + SCX_ENQ_REIMED is necessary — `rt_stall` shows EXT ≥4% under RT load (Arm C in our challenge proof).
>
> It is not sufficient alone: stock bpfland lacks `scx_rt_guard`; the sched_switch reenqueue path is separate from deadline-server enqueue. Our `rt_guard_stress` selftest + 60s soak passes with L3 (Arm B).
>
> Full evidence: `docs/evidence/scx-1202/CHALLENGE_PROOF_<date>/` — reproducible via `run-linux-ebpf-challenge-proof.sh`.
