#!/usr/bin/env bash
# our-goal-fix-failures.sh — fix + re-verify previously failed eBPF gates (no rider-tracker-api touch).
set -uo pipefail
export REAL_ONLY=1
export ELITE_SRC="${ELITE_SRC:-/opt/elite/src}"
ROOT="${ELITE_SRC}"
G="${ROOT}/benchmarks/ebpf-gates"
OUR="${ROOT}/scripts/oneclick/results/our-goal"
REPORT="${OUR}/END_TO_END_REPORT-LATEST.md"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
TMP="/tmp/our-goal-fix-${STAMP}.log"
SERVER_SCRIPTS="${ROOT}/scripts/server"

exec > >(tee -a "${TMP}") 2>&1
echo "=== our-goal-fix-failures ${STAMP} ==="

# 1) orphan marker on VPS
if [[ ! -f "${ROOT}/bpf/DEPRECATED_ORPHANS.md" ]]; then
  echo "FAIL: bpf/DEPRECATED_ORPHANS.md missing in repo"
  exit 1
fi
echo "OK orphan marker present"

# 2) policy file for X5 (create minimal 80B if missing — forecaster ABI)
POLICY="${POLICY_FILE:-/var/lib/elite/predict-policy.bin}"
if [[ ! -f "${POLICY}" ]]; then
  mkdir -p "$(dirname "${POLICY}")"
  python3 -c "
import struct
open('${POLICY}','wb').write(struct.pack('<80B',*( [3]+[0]*79 )))
"
  echo "OK created minimal policy file ${POLICY}"
else
  echo "OK policy file exists ${POLICY}"
fi

set +e
# 3) XDP policy pin on lo only (eth0 untouched) — PM2 guard active, rider excluded
if [[ -x "${SERVER_SCRIPTS}/safe-proof-prep.sh" ]]; then
  bash "${SERVER_SCRIPTS}/safe-proof-prep.sh" || echo "WARN safe-proof-prep partial"
fi
POLICY_PIN="/sys/fs/bpf/elite/policy"
if [[ ! -e "${POLICY_PIN}" ]] && command -v bpftool >/dev/null 2>&1; then
  id="$(bpftool map show 2>/dev/null | awk -F: '/name elite_policy/ {gsub(/:/,"",$1); print $1; exit}' || true)"
  if [[ -n "${id}" ]]; then
    mkdir -p /sys/fs/bpf/elite
    bpftool map pin id "${id}" "${POLICY_PIN}" 2>/dev/null && echo "OK pinned policy id=${id}"
  fi
fi
bash "${SERVER_SCRIPTS}/xdp-attach.sh" status 2>&1 || true
if xdp-loader status 2>/dev/null | grep -q xdp_mitigator; then
  mkdir -p /opt/elite-build/logs
  echo "XDP_ATTACH_OK" > /opt/elite-build/logs/xdp-attach-latest.verdict
  echo "OK xdp_mitigator loaded on lo"
fi

# 4) re-verify failed gates
FAIL=0
set +e
check() {
  local name="$1"; shift
  echo "--- verify: ${name} ---"
  if "$@"; then
    echo "${name}=PASS"
  else
    echo "${name}=FAIL"
    FAIL=$((FAIL + 1))
  fi
}

check "line-audit" bash "${G}/ebpf-line-audit.sh"
check "future-holes" bash "${G}/ebpf-future-holes.sh"
check "ebpf-xray" bash "${ROOT}/scripts/oneclick/ebpf-xray-real-proof.sh"
bash "${G}/global-ebpf-aggregate.sh" || true

# 5) append remediation to same report file
{
  echo ""
  echo "---"
  echo ""
  echo "## Remediation run (${STAMP})"
  echo "- **rider-tracker-api**: not touched (PM2 guard active, restart drift excluded)"
  echo "- **policy_pin**: $(test -e ${POLICY_PIN} && echo present || echo missing)"
  echo "- **DEPRECATED_ORPHANS.md**: $(test -f ${ROOT}/bpf/DEPRECATED_ORPHANS.md && echo OK || echo MISSING)"
  echo ""
  echo "### Re-verify results"
  echo '```'
  grep -E '^(line-audit|future-holes|ebpf-xray)=' "${TMP}" || true
  cat "${OUR}/GLOBAL_EBPF_VERDICT.txt" 2>/dev/null || true
  latest_xray="$(ls -td "${ROOT}"/scripts/oneclick/results/ebpf-xray-* 2>/dev/null | head -1 || true)"
  if [[ -n "${latest_xray}" && -f "${latest_xray}/verdict.txt" ]]; then
    echo "xray_verdict=$(cat "${latest_xray}/verdict.txt")"
    grep -E '^\[(PASS|FAIL)\]' "${latest_xray}/xray.log" 2>/dev/null || true
  fi
  echo '```'
  echo ""
  echo "### fix log"
  echo "Full log: ${TMP}"
} >> "${REPORT}"

echo "FIX_FAILURES_DONE fail=${FAIL} report=${REPORT}"
exit "${FAIL}"
