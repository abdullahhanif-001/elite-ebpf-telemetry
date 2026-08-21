#!/usr/bin/env bash
# Contabo / VPS proof for Elite Physics Pack — hit all exporters, sample CPU.
# Does not invent BPF; verifies OSS compose endpoints.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "${SCRIPT_DIR}/versions.env"

OUT="${PHYSICS_PACK_PROOF_OUT:-/tmp/elite-physics-pack-proof-$(date +%Y%m%d-%H%M%S).log}"
FAIL=0

exec > >(tee "${OUT}") 2>&1
echo "=== ELITE PHYSICS PACK PROOF $(date -Is) ==="
echo "Pinned: ebpf_exporter=${EBPF_EXPORTER_VERSION} ig=${IG_VERSION}"

record() {
  local id="$1" msg="$2" ok="$3"
  if [[ "${ok}" == "PASS" ]]; then
    echo "[${id}] PASS: ${msg}"
  else
    echo "[${id}] FAIL: ${msg}"
    FAIL=$((FAIL + 1))
  fi
}

check_http() {
  local id="$1" url="$2" needle="$3"
  local code body
  code="$(curl -s -o /tmp/epp-body.txt -w '%{http_code}' --connect-timeout 3 "${url}" 2>/dev/null || echo 000)"
  body="$(cat /tmp/epp-body.txt 2>/dev/null || true)"
  if [[ "${code}" != "200" ]]; then
    record "${id}" "${url} -> HTTP ${code}" FAIL
    return
  fi
  if [[ -n "${needle}" ]] && ! grep -qE "${needle}" <<<"${body}"; then
    record "${id}" "${url} missing /${needle}/" FAIL
    return
  fi
  local n
  n="$(grep -cE '^[a-zA-Z_]' <<<"${body}" || true)"
  record "${id}" "${url} OK (${n} metric lines, matched ${needle:-any})" PASS
}

echo "--- P-01 Elite agent ---"
check_http P-01 "http://${ELITE_METRICS_LISTEN}/metrics" '^elite_'

echo "--- P-02 ebpf_exporter ---"
check_http P-02 "http://${EBPF_EXPORTER_LISTEN}/metrics" 'softirq_wait_seconds|kfree_skb_total|shrink_node_latency|tcp_retransmit'

echo "--- P-03 Inspektor Gadget metrics (optional) ---"
code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 "http://${IG_METRICS_LISTEN}/metrics" 2>/dev/null || echo 000)"
if [[ "${code}" == "200" ]]; then
  record P-03 "ig metrics :2224 up" PASS
else
  record P-03 "ig metrics :2224 not required (got ${code}) — optional unit" PASS
fi

echo "--- P-04 BCC tools present (optional) ---"
if command -v softirqs-bpfcc >/dev/null 2>&1 || command -v softirqs >/dev/null 2>&1; then
  record P-04 "bpfcc softirqs tool present" PASS
else
  record P-04 "bpfcc softirqs missing (optional apt)" PASS
fi

echo "--- P-05 scrape glue file ---"
if [[ -f "${SCRIPT_DIR}/prometheus-scrape.yml" ]]; then
  record P-05 "prometheus-scrape.yml present" PASS
else
  record P-05 "prometheus-scrape.yml missing" FAIL
fi

echo "--- P-06 grafana scorecard ---"
if [[ -f "${SCRIPT_DIR}/grafana-elite-physics-pack.json" ]]; then
  record P-06 "grafana dashboard JSON present" PASS
else
  record P-06 "grafana dashboard missing" FAIL
fi

echo "--- P-07 process CPU snapshot (5s) ---"
for proc in elite-agent ebpf_exporter ig; do
  pid="$(pgrep -x "${proc}" | head -n1 || true)"
  if [[ -z "${pid}" ]]; then
    echo "  ${proc}: not running"
    continue
  fi
  # %cpu from ps (instantaneous); soak scripts can extend
  cpu="$(ps -p "${pid}" -o %cpu= 2>/dev/null | tr -d ' ' || echo '?')"
  echo "  ${proc} pid=${pid} cpu%=${cpu}"
done
record P-07 "CPU snapshot printed (compare under soak manually)" PASS

echo "--- P-08 comparison notes (docs) ---"
cat <<'EOF'
Scorecard vs Retina/Hubble (honest):
  - CNI required? Elite Physics Pack VPS path: no. Retina/Hubble: K8s-oriented.
  - Fate ledger? Not claimed; use kfree_skb (exporter) + elite packetloss side-by-side.
  - MM pressure signal? shrinklat from Cloudflare examples (not custom Elite BPF).
  - Self-metered probe budget? systemd CPUQuota on exporter only.
  - Hook tournament? Not claimed; upstream CO-RE/BTF only.
EOF
record P-08 "comparison notes emitted" PASS

echo "=== SUMMARY fail=${FAIL} log=${OUT} ==="
exit "${FAIL}"
