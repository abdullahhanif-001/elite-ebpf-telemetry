#!/usr/bin/env bash
# Elite agent overhead benchmark — Kubernetes or systemd mode
set -euo pipefail

MODE="kubernetes"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--mode kubernetes|systemd]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "$MODE" in
  kubernetes)
    NAMESPACE="${ELITE_NAMESPACE:-elite}"
    DURATION="${BENCH_DURATION:-60}"
    THRESHOLD="${CPU_THRESHOLD:-0.01}"

    echo "== Elite overhead benchmark (${DURATION}s, kubernetes) =="

    if ! kubectl get daemonset elite-agent -n "$NAMESPACE" &>/dev/null; then
      echo "FAIL: elite-agent not found in namespace $NAMESPACE"
      exit 1
    fi

    POD=$(kubectl get pod -n "$NAMESPACE" -l app=elite-agent -o jsonpath='{.items[0].metadata.name}')
    echo "Target pod: $POD"

    samples=()
    end=$((SECONDS + DURATION))
    while [[ $SECONDS -lt $end ]]; do
      cpu=$(kubectl top pod -n "$NAMESPACE" "$POD" --no-headers 2>/dev/null | awk '{print $2}' | sed 's/m$//' || echo "0")
      samples+=("$cpu")
      sleep 5
    done

    total=0
    for s in "${samples[@]}"; do
      total=$((total + s))
    done
    avg=$((total / ${#samples[@]}))
    ratio=$(echo "scale=4; $avg / 1000" | bc)

    echo "avg_cpu_millicores=$avg ratio=$ratio threshold=$THRESHOLD"

    if awk "BEGIN {exit !($ratio < $THRESHOLD)}"; then
      echo "PASS: elite_agent_cpu_ratio=$ratio (<$THRESHOLD)"
      exit 0
    else
      echo "FAIL: elite_agent_cpu_ratio=$ratio (>=$THRESHOLD)"
      exit 1
    fi
    ;;
  systemd)
    exec bash "$ROOT/deploy/contabo/run-overhead-systemd.sh"
    ;;
  *)
    echo "FAIL: unknown mode $MODE (use kubernetes or systemd)" >&2
    exit 1
    ;;
esac
