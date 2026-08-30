#!/usr/bin/env bash
# common.sh — REAL_ONLY enforcement for sched_ext gate scripts.
set -euo pipefail

export REAL_ONLY="${REAL_ONLY:-1}"

real_only_gate() {
  [[ "${REAL_ONLY}" == "1" ]] || {
    echo "FAIL: mock tests forbidden (set REAL_ONLY=1)" >&2
    exit 1
  }
}

script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

repo_root() {
  cd "$(script_dir)/../.." && pwd
}

SCX_VPS_HOST="${SCX_VPS_HOST:-root@169.58.83.156}"
SCX_SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=15
  -o StrictHostKeyChecking=accept-new
)
_id_file="${HOME}/.ssh/id_rsa_contabo"
if [[ -f "${_id_file}" ]]; then
  SCX_SSH_OPTS+=(-i "${_id_file}")
fi
SCX_EXPECTED_HOST="${SCX_EXPECTED_HOST:-vmi3469243}"
SCX_KERNEL_BUILD="${SCX_KERNEL_BUILD:-/opt/scx-kernel-build}"
SCX_ROOT="${SCX_ROOT:-/opt/scx}"
ELITE_SRC="${ELITE_SRC:-/opt/elite/src}"

real_only_gate
