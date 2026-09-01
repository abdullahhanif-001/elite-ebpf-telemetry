# SCX#1202 — Google / Interview Verification Brief

**Author:** Abdullah Hanif  
**Date:** 2026-09-01  
**Claim level:** Verified fix on sched_ext kernel; upstream merge pending

---

## 1. Problem

[sched-ext/scx#1202](https://github.com/sched-ext/scx/issues/1202) — RT tasks monopolize CPU → EXT scheduler runnable tasks stall → kernel watchdog ejects BPF scheduler with `SCX_EXIT_ERROR_STALL` (false positive).

## 2. Your contribution

Three-layer fix:

| Layer | Component | Your work |
|-------|-----------|-----------|
| L1 | ext_server DL server | Tested on VPS (Andrea Righi branch) |
| L2 | RT-aware watchdog (`scx_stall_caused_by_rt`) | Authored patch for LKML |
| L3 | `scx_rt_guard.bpf.h` BPF interceptor | Authored header + selftests + upstream PR |

Also built verification gates: Holy Grail H1–H12, `RT_GUARD_PASS`, committed evidence bundle.

## 3. Proof (reproducible)

**Static verify (any laptop, 30 seconds):**

```bash
git clone https://github.com/abdullahhanif-001/elite-ebpf-telemetry.git
cd elite-ebpf-telemetry && git checkout scx-1202-verified-20260901
bash scripts/verify-scx-1202-evidence.sh
# → SCX1202_EVIDENCE_VERIFY=PASS
```

**Evidence bundle:** [docs/evidence/scx-1202/VERIFICATION_20260901-045612/](VERIFICATION_20260901-045612/)

| Verdict | Result |
|---------|--------|
| `RT_GUARD_PASS` | `fail=0` |
| `HOLY_GRAIL_1202_SOLVED` | `YES` 12/12 |
| `GLOBAL_EBPF` | `fail=0` |
| `RT_GUARD_FLOOD` | `fail=0` |

**Live (sched_ext host only — not valid on generic 6.8 kernels):**

```bash
ssh contabo-server 'export REAL_ONLY=1 ELITE_SRC=/opt/elite/src && \
  bash benchmarks/sched-ext-gates/rt-guard-pass.sh | tail -3'
```

## 4. Upstream status

| Item | Link | Status |
|------|------|--------|
| Layer 3 PR | https://github.com/sched-ext/scx/pull/3780 | OPEN |
| Issue #1202 comment | https://github.com/sched-ext/scx/issues/1202#issuecomment-5489342030 | Posted |
| Layer 2 LKML | [LKML_SUBMISSION.md](LKML_SUBMISSION.md) | Ready to send |

**Fully solved** = PR merged + #1202 closed. Not claimed until then.

## 5. What NOT to claim

- No Google VRP / bug bounty for kernel sched_ext
- Do not say "fully solved" before upstream merge
- Do not use DigitalOcean 6.8 VPS for SCX gate claims

## 6. Known limitations (pre-disclosed)

- **IND-SCX-001:** L3 reenqueues on every RT `sched_switch`; 60s soak passes; scale perf TBD
- **IND-SCX-002:** L2 skips `scx_partial_switch`; FAIR-only hogging edge case documented

## 7. 10-minute demo script

1. Run `verify-scx-1202-evidence.sh` → PASS  
2. Show upstream PR #3780 + #1202 comment thread  
3. Optional: live Contabo `rt-guard-pass` tail  
4. Walk through `scheds/include/scx/scx_rt_guard.bpf.h` in PR diff

---

*For maintainers: evidence is independent of author claims — verifier script is in public repo.*
