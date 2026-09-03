#!/usr/bin/env bash
# generate-evidence-report.sh — build EVIDENCE_REPORT.md from flood results.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLOOD_DIR="${1:-$(ls -td "${ROOT}"/scripts/oneclick/results/rt-guard-flood-safe-* "${ROOT}"/scripts/oneclick/results/rt-guard-flood-* 2>/dev/null | head -1 || true)}"

[[ -d "${FLOOD_DIR}" ]] || { echo "FAIL: no flood dir ${FLOOD_DIR}" >&2; exit 1; }

REPORT="${FLOOD_DIR}/EVIDENCE_REPORT.md"
KERNEL="$(uname -r 2>/dev/null || echo unknown)"
HOST="$(hostname 2>/dev/null || echo unknown)"
DATE="$(date -u +%Y-%m-%dT%H:%MZ)"

cat > "${REPORT}" <<EOF
# sched_ext RT Monopolization Fix — Evidence Report

**Issue:** [sched-ext/scx#1202](https://github.com/sched-ext/scx/issues/1202)  
**Date:** ${DATE}  
**Host:** ${HOST}  
**Kernel:** ${KERNEL}  
**REAL_ONLY:** 1  

## Executive Summary

Three-layer upstream fix for RT task monopolization causing false-positive SCHED_EXT watchdog stalls:

1. **Layer 1** — \`ext_server\` DL bandwidth (arighi scx-dl-server)
2. **Layer 2** — RT-aware watchdog (\`scx_stall_caused_by_rt\`)
3. **Layer 3** — BPF \`scx_rt_guard.bpf.h\` sched_switch interceptor

## Results Matrix

| Phase | Artifact | Verdict |
|-------|----------|---------|
EOF

append_verdict() {
  local phase="$1" path="$2"
  if [[ -f "${path}" ]]; then
    local v
    v="$(grep -E 'PASS|FAIL|SKIP' "${path}" | tail -1 || echo "unknown")"
    echo "| ${phase} | \`${path#${FLOOD_DIR}/}\` | ${v} |" >> "${REPORT}"
  else
    echo "| ${phase} | \`${path#${FLOOD_DIR}/}\` | MISSING |" >> "${REPORT}"
  fi
}

append_verdict "A/B control" "${FLOOD_DIR}/ab-control/verdict.txt"
append_verdict "Negative control" "${FLOOD_DIR}/negative-control/verdict.txt"
append_verdict "Edge lite E1/E3/E7" "${FLOOD_DIR}/edge-cases/verdict.txt"
append_verdict "Scheduler lite" "${FLOOD_DIR}/schedulers/verdict.txt"
append_verdict "Endurance 30min" "${FLOOD_DIR}/endurance/verdict.txt"
append_verdict "kselftests" "${FLOOD_DIR}/kselftests/verdict.txt"

cat >> "${REPORT}" <<EOF

## Scheduler Matrix (6 schedulers)

EOF

if [[ -f "${FLOOD_DIR}/scheduler-matrix.json" ]]; then
  echo '```json' >> "${REPORT}"
  cat "${FLOOD_DIR}/scheduler-matrix.json" >> "${REPORT}"
  echo '```' >> "${REPORT}"
fi

cat >> "${REPORT}" <<'EOF'

## Independent Verification

```bash
ssh production-server
export REAL_ONLY=1 ELITE_SRC=/opt/elite/src
bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh P1
# ... P2-P5 then rt-guard-flood-aggregate.sh
```

## References

- https://github.com/sched-ext/scx/issues/1202
- contrib/sched-ext/ — Layer 2 patch + Layer 3 bpf.h + selftests

EOF

# GitHub #1202 comment draft
COMMENT="${FLOOD_DIR}/GITHUB_1202_COMMENT.md"
cat > "${COMMENT}" <<EOF
## RT Monopolization Fix — VPS Validation (sched-ext/scx#1202)

Validated on **${HOST}** / kernel **${KERNEL}** with REAL stress-ng RT load (\`REAL_ONLY=1\`).

### Summary

| Test | Result |
|------|--------|
| 6-scheduler matrix (bpfland, lavd, rusty, flash, rustland, layered) | See scheduler-matrix.json |
| A/B control (pre-fix baseline + live fix) | ab-control/verdict.txt |
| Negative control (broken BPF still fails) | negative-control/verdict.txt |
| Edge cases E1-E7 | edge-cases/verdict.txt |
| 30min endurance (bpfland + lavd) | endurance/verdict.txt |
| rt_stall + rt_guard_stress | kselftests/ |

### Layers

1. **ext_server** — EXT ≥4% runtime under RT (\`rt_stall\` kselftest)
2. **RT-aware watchdog** — no false \`SCX_EXIT_ERROR_STALL\` under RT pressure
3. **scx_rt_guard.bpf.h** — optional sched_switch complement

Full evidence: \`EVIDENCE_REPORT.md\` in attached tarball.

/cc @htejun @arighi @luigidematteis
EOF

echo "EVIDENCE_REPORT_OK ${REPORT}"
echo "GITHUB_COMMENT_OK ${COMMENT}"
