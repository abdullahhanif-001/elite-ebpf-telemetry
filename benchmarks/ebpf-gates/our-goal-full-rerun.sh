#!/usr/bin/env bash
# our-goal-full-rerun.sh — real end-to-end VPS report (CPU/RAM/PM2 + all gates, no mock).
set -euo pipefail
export REAL_ONLY=1
export ELITE_SRC="${ELITE_SRC:-/opt/elite/src}"
ROOT="${ELITE_SRC}"
G="${ROOT}/benchmarks/ebpf-gates"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
OUR="${ROOT}/scripts/oneclick/results/our-goal"
REPORT="${OUR}/END_TO_END_REPORT-LATEST.md"
TMP="/tmp/our-goal-rerun-${STAMP}.log"

mkdir -p "${OUR}"
exec > >(tee -a "${TMP}") 2>&1

section() { echo ""; echo "## $*"; echo ""; }
kv() { echo "- **$1**: $2"; }

capture_vps() {
  local tag="$1"
  section "VPS snapshot — ${tag} ($(date -u +%Y-%m-%dT%H:%MZ))"
  kv "host" "$(hostname -f 2>/dev/null || hostname)"
  kv "kernel" "$(uname -r)"
  kv "uptime" "$(uptime -p 2>/dev/null || uptime)"
  kv "load" "$(cat /proc/loadavg 2>/dev/null || echo n/a)"
  echo ""
  echo '```'
  free -h 2>/dev/null || free
  echo '```'
  echo ""
  echo '```'
  top -bn1 | head -20
  echo '```'
  echo ""
  if command -v pm2 >/dev/null 2>&1; then
    echo "### PM2 processes"
    echo '```'
    pm2 jlist 2>/dev/null | python3 -c "
import json,sys
try:
  d=json.load(sys.stdin)
  for p in d:
    n=p.get('name','?')
    st=p.get('pm2_env',{}).get('status','?')
    mem=p.get('monit',{}).get('memory',0)
    cpu=p.get('monit',{}).get('cpu',0)
    print(f'{n:30s} status={st:10s} cpu={cpu:5.1f}% mem={mem/1024/1024:.1f}MB')
except Exception as e:
  print('pm2 parse err',e)
" 2>/dev/null || pm2 list
    echo '```'
    echo ""
    echo '```'
    pm2 list 2>/dev/null || true
    echo '```'
  else
    echo "PM2: not installed"
  fi
  echo ""
  echo "### Disk"
  echo '```'
  df -h / /opt/elite 2>/dev/null || df -h /
  echo '```'
  echo ""
  echo "### sched_ext / ftrace"
  kv "CONFIG_SCHED_CLASS_EXT" "$(grep -q '^CONFIG_SCHED_CLASS_EXT=y' "/boot/config-$(uname -r)" 2>/dev/null && echo yes || echo no)"
  kv "ftrace_enabled" "$(cat /proc/sys/kernel/ftrace_enabled 2>/dev/null || echo no)"
  echo ""
  echo "### dmesg tail (stall/sched_ext)"
  echo '```'
  dmesg | tail -30 | grep -iE 'stall|sched_ext|SCX_EXIT|error|fail' || dmesg | tail -15
  echo '```'
}

run_gate() {
  local name="$1"; shift
  section "Gate: ${name}"
  echo '```'
  set +e
  "$@" 2>&1
  local rc=$?
  set -e
  echo '```'
  kv "exit_code" "${rc}"
  return 0
}

{
  echo "# End-to-End Global eBPF Report"
  kv "generated" "$(date -u +%Y-%m-%dT%H:%MZ)"
  kv "mode" "REAL_ONLY=1 (no mock)"
  kv "repo" "${ROOT}"
} > "${REPORT}"

capture_vps "BEFORE" >> "${REPORT}"

# shellcheck source=/dev/null
source "${G}/our-goal-log.sh" 2>/dev/null || true

run_gate "D1 inventory" bash "${G}/global-ebpf-inventory.sh" | tee -a "${REPORT}"
run_gate "D1 line-audit" bash "${G}/ebpf-line-audit.sh" | tee -a "${REPORT}"
run_gate "D1 code-audit" bash "${G}/code-audit-gate.sh" | tee -a "${REPORT}"
run_gate "D3 telemetry" bash "${G}/telemetry-probe-gate.sh" | tee -a "${REPORT}"
run_gate "D6 future-holes FH1-FH10" bash "${G}/ebpf-future-holes.sh" | tee -a "${REPORT}"
run_gate "D4 ebpf-xray" bash "${ROOT}/scripts/oneclick/ebpf-xray-real-proof.sh" | tee -a "${REPORT}"
run_gate "D5 go tests" bash -c "cd '${ROOT}' && go test ./pkg/exporter/bpfutil/... ./pkg/forecaster/... -count=1 -v" | tee -a "${REPORT}"
run_gate "D2 holy-grail H1-H12" bash "${G}/holy-grail-verify.sh" | tee -a "${REPORT}"
run_gate "GLOBAL aggregate" bash "${G}/global-ebpf-aggregate.sh" | tee -a "${REPORT}"

capture_vps "AFTER" >> "${REPORT}"

section "Final verdicts" >> "${REPORT}"
for f in GLOBAL_EBPF_VERDICT.txt HOLY_GRAIL_VERDICT.txt; do
  if [[ -f "${OUR}/${f}" ]]; then
    echo "### ${f}" >> "${REPORT}"
    echo '```' >> "${REPORT}"
    cat "${OUR}/${f}" >> "${REPORT}"
    echo '```' >> "${REPORT}"
  fi
done

latest_fh="$(ls -t "${OUR}"/future-holes-*.json 2>/dev/null | head -1 || true)"
if [[ -n "${latest_fh}" ]]; then
  echo "### future-holes (latest)" >> "${REPORT}"
  echo '```json' >> "${REPORT}"
  cat "${latest_fh}" >> "${REPORT}"
  echo '```' >> "${REPORT}"
fi

latest_xray="$(ls -td "${ROOT}"/scripts/oneclick/results/ebpf-xray-* 2>/dev/null | head -1 || true)"
if [[ -n "${latest_xray}" && -f "${latest_xray}/verdict.txt" ]]; then
  echo "### ebpf-xray verdict" >> "${REPORT}"
  echo '```' >> "${REPORT}"
  cat "${latest_xray}/verdict.txt" >> "${REPORT}"
  echo '```' >> "${REPORT}"
fi

section "Full terminal log" >> "${REPORT}"
echo "See: ${TMP}" >> "${REPORT}"
echo '```' >> "${REPORT}"
tail -200 "${TMP}" >> "${REPORT}"
echo '```' >> "${REPORT}"

cp -f "${TMP}" "${OUR}/run-${STAMP}.log" 2>/dev/null || true

echo ""
echo "END_TO_END_REPORT=${REPORT}"
cat "${OUR}/GLOBAL_EBPF_VERDICT.txt" 2>/dev/null || true
cat "${OUR}/HOLY_GRAIL_VERDICT.txt" 2>/dev/null || true
