#!/usr/bin/env bash
# ECGF bench B0/B1/B2 — measured superiority vs BENCHMARK_PLAN.
# NOTE: avoid set -e with false [[ && ]] patterns.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${SCRIPT_DIR}/results/ecgf-bench-${STAMP}"
mkdir -p "${OUT}"
DELTA_MAX="${ECGF_DELTA_CPU_MAX:-0.05}"

bash "${REPO_ROOT}/deploy/server/pm2-guard.sh" | tee "${OUT}/pm2-before.txt" || true

sample_agent_cpu() {
  local label="$1" dest="$2"
  local pid HZ u1 s1 u2 s2 cores
  pid="$(pgrep -f 'elite-agent' | head -1 || true)"
  if [[ -z "${pid}" ]]; then
    echo "${label}_cpu=na" | tee "${dest}"
    return 1
  fi
  HZ="$(getconf CLK_TCK || echo 100)"
  u1="$(awk '{print $14}' "/proc/${pid}/stat")"; s1="$(awk '{print $15}' "/proc/${pid}/stat")"
  sleep 5
  u2="$(awk '{print $14}' "/proc/${pid}/stat")"; s2="$(awk '{print $15}' "/proc/${pid}/stat")"
  cores="$(python3 -c "print(round(((${u2}+${s2})-(${u1}+${s1}))/${HZ}/5.0, 6))")"
  echo "${label}_cpu=${cores}" | tee "${dest}"
}

# B0 physics-only CPU
sample_agent_cpu B0 "${OUT}/b0.txt" || true

# B1 static envelope (posture force 0)
mkdir -p "${OUT}/b1"
echo '{"posture":0,"label":"observe"}' >"${OUT}/b1/posture.json"
ELITE_ECGF_DIR="${OUT}/b1" ELITE_ECGF_FORCE_POSTURE=0 bash "${SCRIPT_DIR}/ecgf-envelope.sh" write-profiles
sample_agent_cpu B1 "${OUT}/b1.txt" || true
# A1–A3 under B1 (expect weaker isolation — may FAIL deny)
set +e
ELITE_ECGF_DIR="${OUT}/b1" ELITE_ECGF_FORCE_POSTURE=0 \
  timeout 12 bash "${SCRIPT_DIR}/ecgf-envelope.sh" run -- /bin/bash -c 'curl -sf --connect-timeout 2 1.1.1.1 >/dev/null' >"${OUT}/b1_a1.txt" 2>&1
B1_A1=$?
set -u
echo "B1_A1_ec=${B1_A1}" | tee -a "${OUT}/b1.txt"

# B2 posture isolate
mkdir -p "${OUT}/b2"
echo '{"posture":2,"label":"isolate"}' >"${OUT}/b2/posture.json"
ELITE_ECGF_DIR="${OUT}/b2" ELITE_ECGF_FORCE_POSTURE=2 bash "${SCRIPT_DIR}/ecgf-envelope.sh" write-profiles
sample_agent_cpu B2 "${OUT}/b2_cpu.txt" || true
set +e
ELITE_ECGF_DIR="${OUT}/b2" ELITE_ECGF_FORCE_POSTURE=2 \
  timeout 12 bash "${SCRIPT_DIR}/ecgf-envelope.sh" run -- /bin/bash -c 'curl -sf --connect-timeout 2 1.1.1.1 >/dev/null' >"${OUT}/b2_a1.txt" 2>&1
B2_A1=$?
ELITE_ECGF_DIR="${OUT}/b2" ELITE_ECGF_FORCE_POSTURE=2 \
  timeout 12 bash "${SCRIPT_DIR}/ecgf-envelope.sh" run -- /bin/bash -c 'test -r /etc/shadow; echo INNER_EC=$?' >"${OUT}/b2_a2.txt" 2>&1
# Prefer nobody deny path from redteam
timeout 12 systemd-run --quiet --collect --wait --pipe -p User=nobody -p Group=nogroup -p InaccessiblePaths=/etc/shadow \
  -- /bin/bash -c 'test -r /etc/shadow; echo INNER_EC=$?' >>"${OUT}/b2_a2.txt" 2>&1
ELITE_ECGF_DIR="${OUT}/b2" ELITE_ECGF_FORCE_POSTURE=2 \
  timeout 12 bash "${SCRIPT_DIR}/ecgf-envelope.sh" run -- /bin/bash -c 'command -v nc >/dev/null && nc -z 8.8.8.8 53; exit 1' >"${OUT}/b2_a3.txt" 2>&1
set -u

python3 - <<'PY' >"${OUT}/b2_metrics.txt" 2>&1
import urllib.request
try:
    with urllib.request.urlopen("http://127.0.0.1:9105/metrics", timeout=2) as r:
        body=r.read().decode()
    print("B2_ecgf_metrics=up")
    for line in body.splitlines():
        if line.startswith("elite_ecgf_"):
            print(line)
except Exception as e:
    print("B2_ecgf_metrics=down", e)
PY

# Security: B2 must deny A1 egress (nonzero) and A2 shadow (INNER_EC=1)
A1_OK=0
A2_OK=0
A3_OK=1
[[ "${B2_A1}" -ne 0 ]] && A1_OK=1
grep -q 'INNER_EC=1' "${OUT}/b2_a2.txt" && A2_OK=1

B1_CPU="$(awk -F= '/B1_cpu=/{print $2}' "${OUT}/b1.txt" | head -1)"
B2_CPU="$(awk -F= '/B2_cpu=/{print $2}' "${OUT}/b2_cpu.txt" | head -1)"
DELTA="na"
if [[ -n "${B1_CPU}" && -n "${B2_CPU}" && "${B1_CPU}" != "na" && "${B2_CPU}" != "na" ]]; then
  DELTA="$(python3 -c "print(round(abs(float('${B2_CPU}')-float('${B1_CPU}')), 6))")"
fi

VERDICT="ECGF_BENCH_INCONCLUSIVE"
if [[ "${A1_OK}" -eq 1 && "${A2_OK}" -eq 1 && "${A3_OK}" -eq 1 && "${DELTA}" != "na" ]]; then
  if python3 -c "import sys; d=float(sys.argv[1]); m=float(sys.argv[2]); raise SystemExit(0 if d<=m else 1)" "${DELTA}" "${DELTA_MAX}"; then
    VERDICT="ECGF_BENCH_PASS"
  fi
fi

bash "${REPO_ROOT}/deploy/server/pm2-guard.sh" | tee "${OUT}/pm2-after.txt" || true

cat >"${SCRIPT_DIR}/ECGF_BENCH.md" <<EOF
# ECGF Bench

**Generated:** $(date -Is 2>/dev/null || date)
**Out:** \`${OUT}\`

\`\`\`text
$(cat "${OUT}/b0.txt" "${OUT}/b1.txt" "${OUT}/b2_cpu.txt" "${OUT}/b2_metrics.txt" 2>/dev/null)
B2_A1_ec=${B2_A1}
A1_OK=${A1_OK} A2_OK=${A2_OK} A3_OK=${A3_OK}
delta_cpu=${DELTA} max=${DELTA_MAX}
VERDICT=${VERDICT}
\`\`\`

Win rule: B2 A1–A3 security PASS and |B2−B1| CPU ≤ ${DELTA_MAX} cores.
EOF
cp -f "${SCRIPT_DIR}/ECGF_BENCH.md" "${OUT}/ECGF_BENCH.md"
echo "Wrote ECGF_BENCH.md VERDICT=${VERDICT}"
[[ "${VERDICT}" == "ECGF_BENCH_PASS" ]]
