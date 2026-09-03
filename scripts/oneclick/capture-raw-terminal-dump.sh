#!/usr/bin/env bash
# capture-raw-terminal-dump.sh — full VPS session log for gate verification.
set -uo pipefail
RAW="${ELITE_RAW_DUMP:-/opt/elite-build/logs/RAW_TERMINAL_DUMP_20260830.txt}"
SRC="${ELITE_SRC:-/opt/elite/src}"
BUILD="${ELITE_BUILD_ROOT:-/opt/elite-build}"

exec >"${RAW}" 2>&1

echo "=== VPS terminal capture ==="
echo "START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "HOST=$(hostname)"
echo "KERNEL=$(uname -r)"
echo "USER=$(whoami)"
echo "PWD=$(pwd)"
echo "ELITE_SRC=${SRC}"
echo ""

run_cmd() {
  echo ""
  echo "################################################################"
  echo "### CMD: $*"
  echo "################################################################"
  "$@"
  echo "### EXIT: $?"
}

run_cmd systemctl is-active elite-agent

echo ""
echo "################################################################"
echo "### CMD: curl http://127.0.0.1:9102/metrics | grep ^elite_predict_"
echo "################################################################"
curl -fsS --max-time 15 http://127.0.0.1:9102/metrics | grep -E '^elite_predict_' || echo "CURL_OR_GREP_FAIL"
echo "### EXIT: $?"

run_cmd xdp-loader unload --all eth0
run_cmd xdp-loader status
run_cmd bpftool net show
run_cmd bpftool net show dev eth0
run_cmd bpftool net show dev lo
run_cmd bpftool map show pinned /sys/fs/bpf/elite/policy
run_cmd bpftool map show name elite_policy

export ELITE_POLICY_PIN=/sys/fs/bpf/elite/policy
export ELITE_BUILD_ROOT="${BUILD}"
export ELITE_SRC="${SRC}"
export ELITE_XDP_IFACE=lo
export ELITE_XDP_FORCE=1

echo ""
echo "################################################################"
echo "### CMD: w4-xdp-inject-latency.sh (FULL)"
echo "################################################################"
bash "${SRC}/benchmarks/server-gates/w4-xdp-inject-latency.sh"
echo "### EXIT: $?"

echo ""
echo "################################################################"
echo "### CMD: go test -bench=BenchmarkSyncPolicyToBPFMap -benchtime=500x -count=3"
echo "################################################################"
cd "${SRC}" && go test -run='^$' -bench=BenchmarkSyncPolicyToBPFMap -benchtime=500x -count=3 ./pkg/forecaster/
echo "### EXIT: $?"

echo ""
echo "################################################################"
echo "### CMD: w5-xdp-graduated-shed.sh (FULL)"
echo "################################################################"
bash "${SRC}/benchmarks/server-gates/w5-xdp-graduated-shed.sh"
echo "### EXIT: $?"

echo ""
echo "################################################################"
echo "### CMD: thundering-herd/run.sh (FULL)"
echo "################################################################"
bash "${SRC}/benchmarks/thundering-herd/run.sh"
echo "### EXIT: $?"

echo ""
echo "################################################################"
echo "### CMD: zero-buffer-root-verify.sh (FULL)"
echo "################################################################"
bash "${SRC}/scripts/oneclick/zero-buffer-root-verify.sh"
echo "### EXIT: $?"

echo ""
echo "END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "RAW_DUMP_FILE=${RAW}"
wc -c "${RAW}"
echo "RAW_DUMP_COMPLETE"
