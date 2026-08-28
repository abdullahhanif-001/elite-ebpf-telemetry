#!/usr/bin/env bash
# Category #1 bakeoff — same Contabo host, named peers (CLAIM_CHARTER).
# Never touch PM2 apps.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${SCRIPT_DIR}/results/category-bakeoff-${STAMP}"
mkdir -p "${OUT}"
REPEATS="${BAKEOFF_REPEATS:-3}"
SAMPLE_SEC="${BAKEOFF_SAMPLE_SEC:-3}"

pm2_ok() {
  bash "${REPO_ROOT}/deploy/contabo/pm2-guard.sh" >"${OUT}/pm2.txt" 2>&1 && grep -q PM2_GUARD_OK "${OUT}/pm2.txt"
}

sample_proc() {
  local pat="$1" label="$2" dest="$3"
  local pid cores rss HZ u1 s1 u2 s2
  pid="$(pgrep -f "${pat}" | head -1 || true)"
  if [[ -z "${pid}" ]]; then
    echo "${label}_cpu=na ${label}_rss_mb=na" | tee -a "${dest}"
    return 1
  fi
  HZ="$(getconf CLK_TCK || echo 100)"
  u1="$(awk '{print $14}' "/proc/${pid}/stat")"; s1="$(awk '{print $15}' "/proc/${pid}/stat")"
  sleep "${SAMPLE_SEC}"
  u2="$(awk '{print $14}' "/proc/${pid}/stat")"; s2="$(awk '{print $15}' "/proc/${pid}/stat")"
  cores="$(python3 -c "print(round(((${u2}+${s2})-(${u1}+${s1}))/${HZ}/${SAMPLE_SEC}.0, 6))")"
  rss="$(awk '/VmRSS/{printf "%.1f", $2/1024}' "/proc/${pid}/status")"
  echo "${label}_cpu=${cores} ${label}_rss_mb=${rss} pid=${pid}" | tee -a "${dest}"
  return 0
}

med_of() {
  python3 -c "import sys; v=[float(x) for x in sys.argv[1:] if x not in ('','na')]; print(v[len(v)//2] if v else 'na')" "$@"
}

echo "=== CATEGORY BAKEOFF ${STAMP} ==="
if pm2_ok; then echo "PM2_GUARD_OK" >"${OUT}/pm2-status.txt"; else echo "PM2_SKIP" >"${OUT}/pm2-status.txt"; fi

: >"${OUT}/elite_samples.txt"
i=0
while [[ "${i}" -lt "${REPEATS}" ]]; do
  sample_proc 'elite-agent' elite "${OUT}/elite_samples.txt" || true
  i=$((i + 1))
done
mapfile -t elite_cpus < <(awk '{for(i=1;i<=NF;i++) if($i~/^elite_cpu=/){split($i,a,"="); if(a[2]!="na") print a[2]}}' "${OUT}/elite_samples.txt")
mapfile -t elite_rss < <(awk '{for(i=1;i<=NF;i++) if($i~/^elite_rss_mb=/){split($i,a,"="); if(a[2]!="na") print a[2]}}' "${OUT}/elite_samples.txt")
ELITE_CPU_MED="$(med_of "${elite_cpus[@]:-}")"
ELITE_RSS_MED="$(med_of "${elite_rss[@]:-}")"

: >"${OUT}/node_samples.txt"
NODE_PRESENT=0
if pgrep -f node_exporter >/dev/null 2>&1; then
  NODE_PRESENT=1
  i=0
  while [[ "${i}" -lt "${REPEATS}" ]]; do
    sample_proc 'node_exporter' node "${OUT}/node_samples.txt" || true
    i=$((i + 1))
  done
fi
mapfile -t node_cpus < <(awk '{for(i=1;i<=NF;i++) if($i~/^node_cpu=/){split($i,a,"="); if(a[2]!="na") print a[2]}}' "${OUT}/node_samples.txt")
mapfile -t node_rss < <(awk '{for(i=1;i<=NF;i++) if($i~/^node_rss_mb=/){split($i,a,"="); if(a[2]!="na") print a[2]}}' "${OUT}/node_samples.txt")
NODE_CPU_MED="$(med_of "${node_cpus[@]:-}")"
NODE_RSS_MED="$(med_of "${node_rss[@]:-}")"

PRED_N=0
DCIC_N=0
PRED_N="$(curl -sf --max-time 2 http://127.0.0.1:9102/metrics 2>/dev/null | grep -c elite_predict || true)"
DCIC_N="$(curl -sf --max-time 2 http://127.0.0.1:9103/metrics 2>/dev/null | grep -c elite_dcic || true)"
LIVE=0
SOFT=0
[[ "${PRED_N}" -gt 0 ]] && LIVE=1
[[ "${DCIC_N}" -gt 0 ]] && SOFT=1

WIN=1
REASONS="none"
if [[ "${LIVE}" -ne 1 ]]; then WIN=0; REASONS="no_live_predict"; fi
if [[ "${SOFT}" -ne 1 ]]; then WIN=0; REASONS="${REASONS};no_soft_dcic"; fi

echo "node_exporter_present=${NODE_PRESENT}" >"${OUT}/node_absent.txt"
if [[ "${ELITE_CPU_MED}" != "na" ]]; then
  if python3 -c "import sys; raise SystemExit(0 if float(sys.argv[1])<=0.05 else 1)" "${ELITE_CPU_MED}"; then
    echo PASS >"${OUT}/overhead_gate.txt"
  else
    echo FAIL >"${OUT}/overhead_gate.txt"
    WIN=0
    REASONS="${REASONS};elite_cpu_gt_0.05"
  fi
fi

VERDICT="CATEGORY_BAKEOFF_FAIL"
if [[ "${WIN}" -eq 1 ]]; then
  VERDICT="CATEGORY_BAKEOFF_PASS"
fi

SOFT_YES=no
LIVE_YES=no
[[ "${SOFT}" -eq 1 ]] && SOFT_YES=yes
[[ "${LIVE}" -eq 1 ]] && LIVE_YES=yes

DOC="${REPO_ROOT}/docs/CATEGORY_NUMBER_ONE_SCORECARD.md"
{
  echo "# Category Number One Scorecard"
  echo ""
  echo "**Generated:** $(date -Is 2>/dev/null || date)"
  echo "**Host out:** \`${OUT}\`"
  echo ""
  echo "See [CLAIM_CHARTER.md](CLAIM_CHARTER.md)."
  echo ""
  echo '```text'
  echo "ELITE_CATEGORY_NUMBER_ONE"
  echo "elite_cpu_median=${ELITE_CPU_MED}"
  echo "elite_rss_mb_median=${ELITE_RSS_MED}"
  echo "node_cpu_median=${NODE_CPU_MED}"
  echo "node_rss_mb_median=${NODE_RSS_MED}"
  echo "live_predict=${LIVE}"
  echo "soft_dcic=${SOFT}"
  echo "node_exporter_present=${NODE_PRESENT}"
  echo "VERDICT=${VERDICT}"
  echo "reasons=${REASONS}"
  echo '```'
  echo ""
  echo "| Peer | CPU cores (median) | RSS MB | Soft actuate | Live predict |"
  echo "|------|-------------------:|-------:|:------------:|:------------:|"
  echo "| Elite closed-loop | ${ELITE_CPU_MED} | ${ELITE_RSS_MED} | ${SOFT_YES} | ${LIVE_YES} |"
  echo "| P-node (node_exporter) | ${NODE_CPU_MED} | ${NODE_RSS_MED} | no | no |"
  echo "| P-static (forecast off) | n/a this run | n/a | no | no |"
  echo "| P-open (no Soft DCIC) | n/a this run | n/a | no | n/a |"
  echo ""
  echo "**Win rule applied:** Elite must expose elite_predict_* + Soft DCIC metrics and keep median agent CPU <= 0.05 cores; node_exporter compared when present (capability: Soft actuate + live predict)."
} >"${DOC}"
cp -f "${DOC}" "${OUT}/CATEGORY_NUMBER_ONE_SCORECARD.md"
echo "VERDICT=${VERDICT}" | tee "${OUT}/verdict.txt"
if [[ "${WIN}" -eq 1 ]]; then
  exit 0
fi
exit 1
