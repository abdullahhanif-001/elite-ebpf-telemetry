# SCX#1202 — Committed Verification Evidence

Independent auditors: start here. This directory contains **sanitized verdict lines** from live Contabo VPS runs (`REAL_ONLY=1`, no mocks). Raw logs under `scripts/oneclick/results/` remain local and gitignored.

## Host requirements

| Host | sched_ext | Valid for SCX#1202 proof |
|------|-----------|---------------------------|
| Contabo VPS (4 vCPU, kernel 6.19-rc7 + `CONFIG_SCHED_CLASS_EXT=y`) | YES | **Only valid proof host** |
| Generic 6.8 kernels (e.g. DigitalOcean audit VPS) | NO | **Cannot run SCX gates** — Elite security audit only |

## Quick verify (no VPS)

```bash
bash scripts/verify-scx-1202-evidence.sh
```

Exit 0 = committed evidence bundle passes static checks.

## Reproduce on sched_ext host

```bash
export REAL_ONLY=1 ELITE_SRC=/opt/elite/src
bash scripts/contabo/run-scx-1202-evidence.sh
# Output: docs/evidence/scx-1202/VERIFICATION_<timestamp>/
```

Or run gates individually:

```bash
bash benchmarks/sched-ext-gates/rt-guard-pass.sh      # → RT_GUARD_PASS fail=0
bash benchmarks/ebpf-gates/holy-grail-verify.sh       # → HOLY_GRAIL_1202_SOLVED=YES
bash benchmarks/ebpf-gates/global-ebpf-aggregate.sh   # → GLOBAL result=PASS fail=0
bash benchmarks/sched-ext-gates/rt-guard-flood-aggregate.sh  # → RT_GUARD_FLOOD_PASS
```

## Expected verdict lines

| File | Required content |
|------|------------------|
| `01-RT_GUARD_PASS.verdict` | `RT_GUARD_PASS fail=0` |
| `02-HOLY_GRAIL.verdict` | `HOLY_GRAIL_1202_SOLVED=YES fail=0 checks=12/12` |
| `03-GLOBAL.verdict` | `fail=0` and/or `GLOBAL result=PASS` |
| `04-FLOOD.verdict` | `RT_GUARD_FLOOD_PASS fail=0` or flood-safe preflight PASS |

## Claim language

- **Verified:** RT-guard fix passes G0–G6 + Holy Grail H1–H12 on sched_ext kernel.
- **Not claimed:** Upstream issue [sched-ext/scx#1202](https://github.com/sched-ext/scx/issues/1202) closed — Layer 3 PR pending.

## Known limitations (IND-SCX audit)

- **IND-SCX-001:** Layer 3 `scx_rt_guard` reenqueues on RT `sched_switch`; 60s soak passes but large-scale performance not measured.
- **IND-SCX-002:** Layer 2 watchdog skips `scx_partial_switch` mode; FAIR-only CPU hogging may still false-stall — partial fix.

## Related docs

- [GLOBAL_EBPF_VERIFICATION_REPORT.md](../GLOBAL_EBPF_VERIFICATION_REPORT.md)
- [contrib/sched-ext/EVIDENCE_REPORT.md](../../contrib/sched-ext/EVIDENCE_REPORT.md)
- [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md)
