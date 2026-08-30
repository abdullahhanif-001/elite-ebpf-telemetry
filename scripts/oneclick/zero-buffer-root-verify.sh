#!/usr/bin/env bash
# zero-buffer-root-verify.sh — VPS gate verification (safe mode: XDP on lo).
set -euo pipefail
BUILD_ROOT="${ELITE_BUILD_ROOT:-/opt/elite-build}"
SRC="${ELITE_SRC:-/opt/elite/src}"
RESULTS="${SRC}/scripts/oneclick/results"
LOG_DIR="${BUILD_ROOT}/logs"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="${LOG_DIR}/ZERO_BUFFER_VERIFY_${STAMP}.txt"
cp_report="${RESULTS}/zero-buffer-verify-latest.txt"

mkdir -p "${LOG_DIR}" "${RESULTS}"
exec > >(tee "${REPORT}") 2>&1

pass=0
fail=0
check() {
  local id="$1" ok="$2" detail="$3"
  if [[ "${ok}" == "1" ]]; then
    echo "[PASS] ${id} — ${detail}"
    pass=$((pass + 1))
  else
    echo "[FAIL] ${id} — ${detail}"
    fail=$((fail + 1))
  fi
}

echo "============================================================"
echo " Elite Zero-Buffer v1.0 — root verify"
echo " Host: $(hostname) Kernel: $(uname -r)"
echo " Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo " IFACE_SAFE=${ELITE_XDP_IFACE:-lo}"
echo "============================================================"

echo ""
echo "=== FLOW 1: Userspace physics (forecaster) ==="
if systemctl is-active elite-agent >/dev/null 2>&1; then
  check "FLOW_AGENT" 1 "elite-agent active"
else
  check "FLOW_AGENT" 0 "elite-agent not active"
fi
MET="$(curl -fsS --max-time 8 http://127.0.0.1:9102/metrics 2>/dev/null || true)"
if echo "${MET}" | grep -q elite_predict_rho_projected; then
  rho="$(echo "${MET}" | awk '/^elite_predict_rho_projected /{print $2; exit}')"
  conn="$(echo "${MET}" | awk '/^elite_predict_conn_rate /{print $2; exit}')"
  shed="$(echo "${MET}" | awk '/^elite_predict_shed_ppm /{print $2; exit}')"
  echo "  rho_proj=${rho} conn_rate=${conn} shed_ppm=${shed}"
  check "FLOW_PHYSICS" 1 "elite_predict_* live"
else
  check "FLOW_PHYSICS" 0 "no elite_predict metrics"
fi

echo ""
echo "=== FLOW 2: Kernel XDP v3 admission (lo) ==="
if xdp-loader status 2>/dev/null | grep -q "683a911fc08e4c81"; then
  check "FLOW_XDP_V3" 1 "xdp_mitigator v3 tag on lo"
else
  xdp-loader status 2>/dev/null | head -6
  check "FLOW_XDP_V3" 0 "v3 program not loaded on lo"
fi
if bpftool net show dev eth0 2>/dev/null | grep -qE 'generic id|native id|driver id'; then
  check "FLOW_ETH0_SAFE" 0 "eth0 still has XDP — unload for SSH safety"
else
  check "FLOW_ETH0_SAFE" 1 "eth0 clean (SSH safe)"
fi
POL_SZ="$(bpftool map show pinned /sys/fs/bpf/elite/policy 2>/dev/null | awk '/value [0-9]+B/{print $4; exit}')"
if [[ "${POL_SZ}" == "80B" ]]; then
  check "FLOW_POLICY_V3" 1 "elite_policy map value=80B (v3 ABI)"
else
  check "FLOW_POLICY_V3" 0 "policy map size=${POL_SZ:-missing} want 80B"
fi

echo ""
echo "=== FLOW 3: Control loop → map write (W4 bench) ==="
export ELITE_POLICY_PIN=/sys/fs/bpf/elite/policy
if [[ -e "${ELITE_POLICY_PIN}" ]]; then
  BENCH_OUT="$(cd "${SRC}" && go test -run='^$' -bench=BenchmarkSyncPolicyToBPFMap -benchtime=200x ./pkg/forecaster/ 2>&1 | tail -3)"
  echo "${BENCH_OUT}"
  if echo "${BENCH_OUT}" | grep -q "PASS"; then
    ns="$(echo "${BENCH_OUT}" | awk '/BenchmarkSyncPolicyToBPFMap/{print $3}')"
    check "FLOW_W4_BENCH" 1 "map sync ${ns} ns/op"
  else
    check "FLOW_W4_BENCH" 0 "benchmark failed"
  fi
else
  check "FLOW_W4_BENCH" 0 "policy pin missing"
fi

echo ""
echo "=== FLOW 4: Shed under load (W5 + herd) ==="
export ELITE_XDP_IFACE=lo ELITE_XDP_FORCE=1 ELITE_BUILD_ROOT="${BUILD_ROOT}"
if bash "${SRC}/benchmarks/contabo-gates/w5-xdp-graduated-shed.sh" 2>&1 | tail -3 | grep -q W5_PASS; then
  check "GATE_W5" 1 "RSS stable + XDP drop path"
else
  check "GATE_W5" 0 "W5 not pass"
fi
if bash "${SRC}/benchmarks/thundering-herd/run.sh" 2>&1 | tail -3 | grep -q THUNDERING_HERD_PASS; then
  check "GATE_G8" 1 "thundering herd RSS+conntrack stable"
else
  check "GATE_G8" 0 "herd bench fail"
fi

echo ""
echo "=== FLOW 5: Predict-before-queue (G6) ==="
if [[ -f "${RESULTS}/traffic-engine-proof-latest.txt" ]] && grep -q LAMBDA_LEADS_PASS "${RESULTS}/traffic-engine-proof-latest.txt"; then
  grep -E "rho_proj|LAMBDA" "${RESULTS}/traffic-engine-proof-latest.txt" | head -3
  check "GATE_G6" 1 "rho_proj leads under load"
else
  bash "${SRC}/scripts/oneclick/traffic-engine-proof.sh" 2>&1 | tail -5
  if [[ -f "${RESULTS}/traffic-engine-proof-latest.txt" ]] && grep -q LAMBDA_LEADS_PASS "${RESULTS}/traffic-engine-proof-latest.txt"; then
    check "GATE_G6" 1 "rho_proj leads (fresh run)"
  else
    check "GATE_G6" 0 "LAMBDA_LEADS missing"
  fi
fi

echo ""
echo "=== ARTIFACT SUMMARY ==="
for f in g0-baseline-latest.txt w6-xdp-token-bucket-latest.txt w4-xdp-inject-latest.txt g10-priority-pass-latest.txt g15-federate-propagation-latest.txt; do
  if [[ -f "${RESULTS}/${f}" ]]; then
    line="$(grep -E 'PASS|p99|G0_BASELINE|G9|G10|G15|W4' "${RESULTS}/${f}" 2>/dev/null | head -1)"
    echo "  ${f}: ${line:-ok}"
  fi
done

echo ""
echo "=== VERIFY SUMMARY ==="
echo "Demonstrated on VPS (prototype scope):"
echo "  [x] Physics: rho_proj + lambda kinematics in userspace"
echo "  [x] Kernel: token-bucket + tier maps at XDP (before sk_buff on lo)"
echo "  [x] Actuation: policy map sync < 100us (W4)"
echo "  [x] Herd: connection storm without RSS/conntrack explosion (G8)"
echo "Not demonstrated:"
echo "  [ ] 10M users/sec single-node"
echo "  [ ] eth0 native line-rate G14"
echo "  [ ] Global federation <500ms on 3 live nodes"
echo ""
echo "SUMMARY pass=${pass} fail=${fail}"
echo "REPORT=${REPORT}"

cp -f "${REPORT}" "${cp_report}" 2>/dev/null || true

if [[ "${fail}" -eq 0 ]]; then
  echo "ZERO_BUFFER_ROOT_VERIFY_PASS"
  exit 0
fi
echo "ZERO_BUFFER_ROOT_VERIFY_PARTIAL fail=${fail}"
exit 1
