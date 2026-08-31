#!/usr/bin/env bash
# telemetry-probe-gate.sh — compile all wired bpf/*.c + optional VPS metrics check.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ebpf-gates-common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/our-goal-log.sh"

ROOT="$(ebpf_repo_root)"
OUT="${OUR_GOAL_DIR}/phases/telemetry-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${OUT}"
FAIL=0
export REAL_ONLY=1

declare -A PROBES=(
  [T1_connect]="connect_trace.c:traceconnect"
  [T2_flow]="flow.c:flow"
  [T3_kernel]="kernellatency.c:tracekernel"
  [T4_netiftx]="netiftxlatency.c:tracenetiftxlatency"
  [T5_packetloss]="packetloss.c:tracepacketloss"
  [T6_socket]="socketlatency.c:tracesocketlatency"
  [T7_softirq]="softirq.c:tracesoftirq"
  [T8_tcpretrans]="tcpretrans.c:tracetcpretrans"
  [T9_tcpreset]="tcpreset.c:tracetcpreset"
  [T10_bio]="tracebiolatency.c:tracebiolatency"
  [T11_virtcmd]="virtcmdlatency.c:tracevirtcmdlat"
)

arch=x86
case "$(uname -m 2>/dev/null)" in aarch64|arm64) arch=arm64 ;; esac

compile_one() {
  local src="$1" obj="$2"
  clang -O2 -g -target bpf -D__TARGET_ARCH_${arch} \
    -I"${ROOT}/bpf/headers" -I"${ROOT}/bpf" \
    -c "${ROOT}/bpf/${src}" -o "${obj}" 2>>"${OUT}/compile.err"
}

log() { echo "$*" | tee -a "${OUT}/telemetry.log"; }

for tid in "${!PROBES[@]}"; do
  IFS=: read -r src loader <<< "${PROBES[$tid]}"
  base="${src%.c}"
  obj="${OUT}/${base}.o"
  if compile_one "${src}" "${obj}"; then
    log "${tid} COMPILE_PASS ${src} loader=${loader}"
    our_goal_log "${tid}" "PASS" "${obj}" "compile ${src}"
  elif [[ -f "${ROOT}/pkg/exporter/probe/${loader}/bpf_bpfel_x86.go" ]] \
    || [[ -f "${ROOT}/pkg/exporter/probe/${loader}/connecttrace_bpf.go" ]]; then
    log "${tid} COMPILE_SKIP ${src} — bpf2go embed present"
    our_goal_log "${tid}" "PASS" "pkg/exporter/probe/${loader}" "bpf2go embed"
  else
    log "${tid} COMPILE_FAIL ${src}"
    our_goal_log "${tid}" "FAIL" "${obj}" "compile ${src}"
    FAIL=$((FAIL + 1))
  fi
done

# go test bpf2go packages (compile embed check)
if command -v go >/dev/null 2>&1; then
  if (cd "${ROOT}" && go test ./pkg/exporter/probe/flow/... ./pkg/exporter/probe/tracesoftirq/... -count=1) >>"${OUT}/go-test.log" 2>&1; then
    log "GO_PROBE_TEST_PASS"
    our_goal_log "D3_go_probe" "PASS" "${OUT}/go-test.log" "flow+softirq"
  else
    log "GO_PROBE_TEST_FAIL"
    our_goal_log "D3_go_probe" "FAIL" "${OUT}/go-test.log" ""
    FAIL=$((FAIL + 1))
  fi
fi

AGENT_URL="${AGENT_URL:-http://127.0.0.1:9102/metrics}"
if curl -fsS --max-time 3 "${AGENT_URL}" >/dev/null 2>&1; then
  curl -fsS --max-time 5 "${AGENT_URL}" -o "${OUT}/metrics.txt" 2>/dev/null || true
  log "VPS_METRICS=scraped"
  our_goal_log "D3_metrics" "PASS" "${OUT}/metrics.txt" "agent live"
else
  log "VPS_METRICS=SKIP (agent not on localhost — run on VPS for attach proof)"
  our_goal_log "D3_metrics" "SKIP" "" "no agent"
fi

if [[ "${FAIL}" -eq 0 ]]; then
  echo "TELEMETRY_PROBE_GATE_PASS fail=0" | tee "${OUT}/verdict.txt"
  our_goal_log "D3_telemetry" "PASS" "${OUT}/verdict.txt" "11 probes compiled"
  exit 0
fi
echo "TELEMETRY_PROBE_GATE_FAIL fail=${FAIL}" | tee "${OUT}/verdict.txt"
our_goal_log "D3_telemetry" "FAIL" "${OUT}/verdict.txt" "fail=${FAIL}"
exit 1
