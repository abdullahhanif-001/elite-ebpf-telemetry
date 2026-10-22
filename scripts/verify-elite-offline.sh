#!/usr/bin/env bash
# verify-elite-offline.sh — full repo proof without a sched_ext VPS.
# Use before interviews/reviews when production server is unavailable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REAL_ONLY="${REAL_ONLY:-1}"
export ELITE_OFFLINE="${ELITE_OFFLINE:-1}"
FAIL=0

step() {
  echo ""
  echo "========== $* =========="
}

run() {
  if "$@"; then
    echo "OK   $*"
  else
    echo "FAIL $*" >&2
    FAIL=$((FAIL + 1))
  fi
}

step "SCX#1202 committed evidence (strict)"
run bash "${ROOT}/scripts/verify-scx-1202-evidence.sh"

step "SCX#1202 matrix cross-check (bundle logs)"
run bash "${ROOT}/scripts/verify-scx1202-matrix-from-bundle.sh"

step "Claim charter"
run bash "${ROOT}/scripts/oneclick/claim-charter-grep.sh"

step "BPF generate (requires clang + llvm-strip)"
if command -v llvm-strip >/dev/null 2>&1; then
  run make -C "${ROOT}" generate-bpf
else
  echo "SKIP generate-bpf (llvm-strip missing — apt install llvm)"
  FAIL=$((FAIL + 1))
fi

step "Go unit tests"
run go test "${ROOT}/pkg/export/..." "${ROOT}/pkg/exporter/..." "${ROOT}/pkg/forecaster/..." \
  "${ROOT}/pkg/dcic/..." "${ROOT}/pkg/llc/..." "${ROOT}/pkg/ecgf/..." "${ROOT}/pkg/elitecontroller/..." \
  -count=1 -timeout 10m
run go test "${ROOT}/cmd/elite-updater/..." -timeout 2m
run bash -c "cd '${ROOT}/pkg/controller' && go mod tidy && go test ./... -timeout 5m"

step "Build binaries"
run make -C "${ROOT}" build-elite-agent build-elite-updater

step "eBPF gates (compile / static)"
run bash "${ROOT}/benchmarks/ebpf-gates/global-ebpf-inventory.sh"
run bash "${ROOT}/benchmarks/ebpf-gates/telemetry-probe-gate.sh"
run bash "${ROOT}/benchmarks/ebpf-gates/ebpf-future-holes.sh"
run bash "${ROOT}/benchmarks/ebpf-gates/code-audit-gate.sh"

step "Layer 3 rt_guard sources (offline static)"
_hdr="${ROOT}/contrib/sched-ext/bpf/scx_rt_guard.bpf.h"
_bpf="${ROOT}/contrib/sched-ext/selftests/rt_guard_stress.bpf.c"
if [[ -f "${_hdr}" && -f "${_bpf}" ]] && grep -q 'SCX_RT_GUARD_SCHED_SWITCH_PROG' "${_hdr}"; then
  echo "OK   rt_guard header + selftest present"
else
  echo "FAIL rt_guard contrib artifacts missing" >&2
  FAIL=$((FAIL + 1))
fi

step "Shell syntax (CI subset)"
run bash -n "${ROOT}/install.sh"
for f in "${ROOT}"/benchmarks/ebpf-gates/*.sh; do
  run bash -n "${f}"
done

if [[ "${FAIL}" -eq 0 ]]; then
  echo ""
  echo "ELITE_OFFLINE_VERIFY=PASS fail=0"
  echo "Note: live sched_ext flood/matrix requires CONFIG_SCHED_CLASS_EXT=y host."
  echo "Committed FULL bundle substitutes for VPS when ELITE_OFFLINE=1."
  exit 0
fi

echo "ELITE_OFFLINE_VERIFY=FAIL fail=${FAIL}" >&2
exit 1
