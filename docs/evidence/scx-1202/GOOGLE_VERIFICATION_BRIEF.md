# SCX#1202 — Google / Interview Verification Brief

**Author:** Abdullah Hanif  
**Date:** 2026-09-03  
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

Also built verification gates: SCX1202 gate matrix H1–H12, `RT_GUARD_PASS`, committed evidence bundle.

## 3. Proof (reproducible)

**Static verify (any machine with bash, ~30 seconds):**

```bash
git clone https://github.com/abdullahhanif-001/elite-ebpf-telemetry.git
cd elite-ebpf-telemetry
bash scripts/verify-scx-1202-evidence.sh
# → SCX1202_EVIDENCE_VERIFY=PASS strict=1
```

**Evidence bundle:** [docs/evidence/scx-1202/VERIFICATION_20260903-012848/](VERIFICATION_20260903-012848/)

| Verdict | Result |
|---------|--------|
| `RT_GUARD_PASS` | `fail=0` |
| `SCX1202_MATRIX_PASS` | `YES` 12/12 |
| `GLOBAL_EBPF` | `fail=0` |
| `RT_GUARD_FLOOD` | `fail=0` |
| `MANIFEST status` | `FULL` |

**Live host fingerprint:**

- Host: `ubuntu-s-4vcpu-8gb-nyc1`
- Kernel: `6.19.0-rc7-scx-dl-g9854922412d3-dirty`
- `CONFIG_SCHED_CLASS_EXT=y`, `CONFIG_FUNCTION_TRACER=y`, `CONFIG_DEBUG_INFO_BTF=y`

## 4. Upstream status

| Item | Link | Status |
|------|------|--------|
| Layer 3 PR | [sched-ext/scx#3780](https://github.com/sched-ext/scx/pull/3780) | OPEN |
| Issue #1202 comment | [comment](https://github.com/sched-ext/scx/issues/1202#issuecomment-5489342030) | Posted |
| Layer 2 LKML | [LKML_SUBMISSION.md](LKML_SUBMISSION.md) | Ready to send |

**Fully solved** = PR merged + #1202 closed. Not claimed until then.

## 5. What NOT to claim

- No Google VRP / bug bounty for kernel sched_ext
- Do not say "fully solved" before upstream merge
- Do not use generic 6.8 kernels for SCX gate claims

## 6. Known limitations (pre-disclosed)

- **LIMIT-SCX-001:** L3 reenqueues on every RT `sched_switch`; 60s soak passes; scale perf TBD
- **LIMIT-SCX-002:** L2 skips `scx_partial_switch`; FAIR-only hogging edge case documented
- **LIMIT-SCX-003:** `scx_lavd` `FAIL_LOAD` on ftrace kernel (BPF arena); matrix accepts 5/6 `PASS_LOADER` + lavd documented skip

## 7. 10-minute demo script

1. Run `verify-scx-1202-evidence.sh` → PASS  
2. Show `MANIFEST.json` → `status=FULL`  
3. Show upstream PR #3780 + #1202 comment thread  
4. Walk through `scheds/include/scx/scx_rt_guard.bpf.h` in PR diff

---

*For maintainers: evidence is reproducible via public verifier — Abdullah Hanif, author — verifier script is in public repo.*
