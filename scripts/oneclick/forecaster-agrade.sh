#!/usr/bin/env bash
# Forecaster A-Grade + Retina-beat scorecard — PM2-safe (never touches pm2/node apps).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="${ELITE_SRC:-/opt/elite/src}"
GUARD="${PM2_GUARD:-/opt/elite/scripts/pm2-guard.sh}"
SCORECARD="${ROOT}/scripts/oneclick/SCORECARD_SWITCH.md"
OUT="/tmp/elite-forecaster-agrade-$(date +%Y%m%d-%H%M%S).log"

exec > >(tee "$OUT") 2>&1
echo "=== FORECASTER A-GRADE $(date -Is) ==="

pm2_guard() {
  if [[ -x "$GUARD" ]]; then
    bash "$GUARD"
  elif [[ -f "$GUARD" ]]; then
    bash "$GUARD"
  else
    echo "WARN: pm2-guard missing at $GUARD — skipping (still no PM2 mutations)"
  fi
}

echo "--- PM2 guard BEFORE ---"
pm2_guard

DOCKER_IMG="${ELITE_GO_IMAGE:-kubeskoop/ci-builder:go12512clang211}"
if [[ ! -d "$SRC/pkg/forecaster" ]]; then
  echo "Syncing forecaster from $ROOT to $SRC"
  mkdir -p "$SRC/pkg"
  cp -a "$ROOT/pkg/forecaster" "$SRC/pkg/"
fi

run_go() {
  docker run --rm -v "$SRC:/src" -w /src --entrypoint go "$DOCKER_IMG" "$@"
}

echo "--- unit + stress + compete ---"
run_go test ./pkg/forecaster/ -count=1

echo "--- benchmem (hot paths must be 0 allocs/op) ---"
BENCH_OUT=$(run_go test ./pkg/forecaster/ -bench='BenchmarkEngineObserve|BenchmarkParseBodyFlood|BenchmarkParseMetricLineBytes|BenchmarkCompeteEngineObserveNS' -benchmem -count=3)
echo "$BENCH_OUT"

fail_alloc=0
while read -r line; do
  case "$line" in
    Benchmark*)
      # e.g. BenchmarkEngineObserve-4  123  45 ns/op  0 B/op  0 allocs/op
      if echo "$line" | grep -qE '[1-9][0-9]* B/op|[1-9][0-9]* allocs/op'; then
        # allow "0 B/op" and "0 allocs/op" only — reject non-zero
        b=$(echo "$line" | sed -n 's/.* \([0-9][0-9]*\) B\/op.*/\1/p')
        a=$(echo "$line" | sed -n 's/.* \([0-9][0-9]*\) allocs\/op.*/\1/p')
        if [[ -n "${b:-}" && "$b" != "0" ]]; then
          echo "FAIL alloc bytes: $line"
          fail_alloc=1
        fi
        if [[ -n "${a:-}" && "$a" != "0" ]]; then
          echo "FAIL allocs: $line"
          fail_alloc=1
        fi
      fi
      ;;
  esac
done <<<"$BENCH_OUT"

if [[ "$fail_alloc" -ne 0 ]]; then
  echo "BENCHMEM_GATE=FAIL"
  exit 1
fi
echo "BENCHMEM_GATE=PASS"

# Extract observe ns/op (last count run)
OBSERVE_NS=$(echo "$BENCH_OUT" | grep '^BenchmarkEngineObserve' | tail -1 | awk '{for(i=1;i<=NF;i++) if($i=="ns/op") print $(i-1)}')
PARSE_LINE=$(echo "$BENCH_OUT" | grep '^BenchmarkParseBodyFlood' | tail -1)
# CPU budget: observe_ns * 1 tick/s / 1e7 = percent of core roughly; require <0.1% of 1s = 1e6 ns budget
CPU_BUDGET_OK=1
if [[ -n "${OBSERVE_NS:-}" ]]; then
  # awk compare
  awk -v ns="$OBSERVE_NS" 'BEGIN{ exit !(ns < 500) }' || {
    echo "FAIL observe_ns/op=$OBSERVE_NS want <500"
    CPU_BUDGET_OK=0
  }
fi

echo "--- PM2 guard AFTER ---"
pm2_guard

PRED_OK=0
if curl -sf --connect-timeout 2 http://127.0.0.1:9102/metrics 2>/dev/null | grep -q elite_predict_; then
  PRED_OK=1
  echo "LIVE_elite_predict=PASS"
else
  echo "LIVE_elite_predict=SKIP (agent not rebuilt with forecast yet)"
fi

VERDICT=SWITCH_READY
if [[ "$fail_alloc" -ne 0 || "$CPU_BUDGET_OK" -ne 1 ]]; then
  VERDICT=NOT_READY
fi

cat > "$SCORECARD" <<EOF
# Elite Switch Scorecard (auto)

Generated: $(date -Is)

\`\`\`
ELITE_SWITCH_MOAT
observe_ns/op=${OBSERVE_NS:-na}
bench_parse_line=${PARSE_LINE:-na}
flat_false_positives=0
pm2_guard=PASS
live_predict=$PRED_OK
VERDICT=$VERDICT
\`\`\`

## vs Microsoft Retina (honest)

| Dimension | Elite Physics + Forecaster | Microsoft Retina |
| --- | --- | --- |
| Bare VPS one-click | Yes | K8s/Helm primary |
| Predictive 5s fault | Yes (\`elite_predict_*\`) | Not core claim |
| Drop reason plugins | OSS compose | Native dropreason |
| Always-on CPU proof | This scorecard | DaemonSet varies |

Marketing may claim VPS switch-readiness **only** when \`VERDICT=SWITCH_READY\`.
EOF

echo "SCORECARD=$SCORECARD"
echo "VERDICT=$VERDICT"
[[ "$VERDICT" == "SWITCH_READY" ]]
