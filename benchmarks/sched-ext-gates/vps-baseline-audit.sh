#!/usr/bin/env bash
# vps-baseline-audit.sh — document VPS state (passes even when sched_ext=NO).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

HOST="${SCX_VPS_HOST}"
EXPECTED="${SCX_EXPECTED_HOST}"
OUT="$(repo_root)/scripts/oneclick/results/rt-guard-baseline-audit-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${OUT}"

out="$(ssh ${SCX_SSH_OPTS} "${HOST}" bash -s <<'REMOTE'
set -euo pipefail
echo "hostname=$(hostname)"
echo "kernel=$(uname -r)"
k="/boot/config-$(uname -r)"
if [[ -f "${k}" ]] && grep -q '^CONFIG_SCHED_CLASS_EXT=y' "${k}"; then
  echo "sched_ext=YES"
else
  echo "sched_ext=NO"
fi
echo "cpus=$(nproc)"
free -h | awk '/^Mem:/ {print "mem_total="$2, "mem_avail="$7}'
df -h / | awk 'NR==2 {print "disk_free="$4}'
swapon --show 2>/dev/null | tail -n +2 | wc -l | awk '{print "swap_count="$1}'
command -v bpftool >/dev/null && echo "bpftool=YES" || echo "bpftool=NO"
command -v clang >/dev/null && echo "clang=YES" || echo "clang=NO"
command -v scx_loader >/dev/null && echo "scx_loader=YES" || echo "scx_loader=NO"
command -v stress-ng >/dev/null && echo "stress_ng=YES" || echo "stress_ng=NO"
test -d /opt/elite/src && echo "elite_src=YES" || echo "elite_src=NO"
pm2 jlist 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print("pm2_apps="+str(len(d)))' 2>/dev/null || echo "pm2_apps=0"
REMOTE
)"

echo "${out}" | tee "${OUT}/baseline.txt"
echo "${out}" | grep -q "hostname=${EXPECTED}" || { echo "FAIL wrong host (expected ${EXPECTED})"; exit 1; }

{
  echo "VPS_BASELINE_AUDIT"
  echo "host=${EXPECTED}"
  echo "generated=$(date -Is 2>/dev/null || date)"
  echo "${out}"
} > "${OUT}/verdict.txt"

echo "VPS_BASELINE_AUDIT_PASS out=${OUT}"
