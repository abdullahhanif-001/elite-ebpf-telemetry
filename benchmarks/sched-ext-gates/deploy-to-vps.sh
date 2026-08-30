#!/usr/bin/env bash
# deploy-to-vps.sh — sync sched_ext gate scripts + contrib to Contabo VPS.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ROOT="$(repo_root)"
HOST="${SCX_VPS_HOST}"
DEST="${ELITE_SRC}"

echo "Deploy sched_ext gates to ${HOST}:${DEST}"

ssh "${SCX_SSH_OPTS[@]}" "${HOST}" "mkdir -p \"${DEST}/benchmarks\" \"${DEST}/scripts/contabo\" \"${DEST}/contrib\" \"${DEST}/scripts/oneclick/results\""

scp "${SCX_SSH_OPTS[@]}" -r "${ROOT}/benchmarks/sched-ext-gates" "${HOST}:${DEST}/benchmarks/"
scp "${SCX_SSH_OPTS[@]}" "${ROOT}/scripts/contabo/sched-ext-vps-prep.sh" "${HOST}:${DEST}/scripts/contabo/"
scp "${SCX_SSH_OPTS[@]}" -r "${ROOT}/contrib/sched-ext" "${HOST}:${DEST}/contrib/"

ssh "${SCX_SSH_OPTS[@]}" "${HOST}" "chmod +x \"${DEST}/benchmarks/sched-ext-gates/*.sh\" \"${DEST}/scripts/contabo/sched-ext-vps-prep.sh\""

echo "DEPLOY_OK ${HOST}:${DEST}"
