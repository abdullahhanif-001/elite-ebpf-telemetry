#!/usr/bin/env bash
# vps-connect-check.sh — hard gate: SSH + hostname + sched_ext=YES.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

HOST="${SCX_VPS_HOST}"
EXPECTED="${SCX_EXPECTED_HOST}"

out="$(ssh "${SCX_SSH_OPTS[@]}" "${HOST}" bash -s <<'REMOTE'
set -euo pipefail
echo "hostname=$(hostname)"
echo "kernel=$(uname -r)"
k="/boot/config-$(uname -r)"
if [[ -f "${k}" ]] && grep -q '^CONFIG_SCHED_CLASS_EXT=y' "${k}"; then
  echo "sched_ext=YES"
else
  echo "sched_ext=NO"
fi
echo "bpftool=$(bpftool version 2>/dev/null | head -1 || echo missing)"
echo "clang=$(clang --version 2>/dev/null | head -1 || echo missing)"
command -v scx_loader >/dev/null && echo "scx_loader=YES" || echo "scx_loader=NO"
command -v stress-ng >/dev/null && echo "stress_ng=YES" || echo "stress_ng=NO"
test -d /opt/scx-kernel-build && echo "kernel_build=YES" || echo "kernel_build=NO"
test -d /opt/scx && echo "scx_root=YES" || echo "scx_root=NO"
REMOTE
)"

echo "${out}"
echo "${out}" | grep -q "hostname=${EXPECTED}" || { echo "FAIL wrong host (expected ${EXPECTED})"; exit 1; }
echo "${out}" | grep -q "sched_ext=YES" || {
  echo "FAIL sched_ext not enabled — run: ssh ${HOST} bash ${ELITE_SRC}/scripts/server/sched-ext-vps-prep.sh"
  exit 1
}
echo "VPS_CONNECT_PASS host=${EXPECTED}"
