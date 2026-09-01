# SCX#1202 — Committed Verification Evidence

Independent auditors: start here. This directory contains **sanitized verdict lines** from live sched_ext proof host runs (`REAL_ONLY=1`, no mocks). Raw logs under `scripts/oneclick/results/` remain local and gitignored.

## Host requirements

| Host | sched_ext | Valid for SCX#1202 proof |
|------|-----------|---------------------------|
| sched_ext proof host (4 vCPU, kernel 6.19-rc7 + `CONFIG_SCHED_CLASS_EXT=y`) | YES | **Only valid proof host** |
| Generic 6.8 kernels (e.g. DigitalOcean audit VPS) | NO | **Cannot run SCX gates** — Elite security audit only |

## Quick verify (no VPS)

```bash
bash scripts/verify-scx-1202-evidence.sh
```

Exit 0 = committed evidence bundle passes static checks (VERIFICATION_* and/or CHALLENGE_PROOF_*).

## Full challenge proof (recommended)

```bash
export REAL_ONLY=1 ELITE_SRC=/opt/elite/src
bash scripts/contabo/run-linux-ebpf-challenge-proof.sh
# Output: docs/evidence/scx-1202/CHALLENGE_PROOF_<YYYYMMDD>/
```

**Tiers:** T1 SCX core (G0–G6) · T2 Andrea A/B + flood P1–P5 · T3 SCX#1202 matrix H1–H12 · T4 Global eBPF D1–D6

**Canonical references:** [TEST_BENCHMARK_REGISTRY.md](../../TEST_BENCHMARK_REGISTRY.md) · [EBPF_FEATURE_INVENTORY.md](../../EBPF_FEATURE_INVENTORY.md)

**Q&A for any question:** [CHALLENGE_QA_PLAYBOOK.md](CHALLENGE_QA_PLAYBOOK.md)

## Legacy single-bundle capture

```bash
bash scripts/contabo/run-scx-1202-evidence.sh
# Output: docs/evidence/scx-1202/VERIFICATION_<timestamp>/
```

## Expected verdict lines

| File | Required content |
|------|------------------|
| `CHALLENGE_VERDICT.txt` | `LINUX_EBPF_CHALLENGE_PASS fail=0` |
| `tier1/01-RT_GUARD_PASS.verdict` | `RT_GUARD_PASS fail=0` |
| `tier2/ANDREA_PROOF.verdict` | `ANDREA_PROOF_PASS fail=0` |
| `tier2/04-FLOOD.verdict` | `RT_GUARD_FLOOD_PASS fail=0` |
| `tier3/02-HOLY_GRAIL.verdict` | `HOLY_GRAIL_1202_SOLVED=YES checks=12/12` |
| `tier4/03-GLOBAL.verdict` | `fail=0` and/or `GLOBAL result=PASS` |

## Claim language

- **Verified:** RT-guard fix passes full challenge suite on sched_ext kernel.
- **Upstream:** PR #3780 **closed** — reopen after `LINUX_EBPF_CHALLENGE_PASS` committed.
- **Not claimed:** Upstream issue [#1202](https://github.com/sched-ext/scx/issues/1202) closed.

## Known limitations (IND-SCX audit)

- **IND-SCX-001:** Layer 3 `scx_rt_guard` reenqueues on RT `sched_switch`; 60s soak passes but large-scale performance not measured.
- **IND-SCX-002:** Layer 2 watchdog skips `scx_partial_switch` mode; FAIR-only CPU hogging may still false-stall — partial fix.

## Related docs

- [TEST_BENCHMARK_REGISTRY.md](../../TEST_BENCHMARK_REGISTRY.md)
- [EBPF_FEATURE_INVENTORY.md](../../EBPF_FEATURE_INVENTORY.md)
- [CHALLENGE_PROOF_20260901/](CHALLENGE_PROOF_20260901/) — full lite challenge bundle
- [ISSUE_1202_REPLY_READY.md](ISSUE_1202_REPLY_READY.md)
- [MAINTAINER_REPLY_PACK.md](MAINTAINER_REPLY_PACK.md)
- [GLOBAL_EBPF_VERIFICATION_REPORT.md](../GLOBAL_EBPF_VERIFICATION_REPORT.md)
- [contrib/sched-ext/EVIDENCE_REPORT.md](../../contrib/sched-ext/EVIDENCE_REPORT.md)
- [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md)
- [GOOGLE_VERIFICATION_BRIEF.md](GOOGLE_VERIFICATION_BRIEF.md)
- [UPSTREAM_PR_TRACKER.md](UPSTREAM_PR_TRACKER.md)
