#!/usr/bin/env bash
# deploy-to-vps.sh — sync sched_ext gate scripts + contrib to Contabo VPS.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ROOT="$(repo_root)"
HOST="${SCX_VPS_HOST}"
DEST="${ELITE_SRC}"

echo "Deploy sched_ext gates to ${HOST}:${DEST}"

# shellcheck disable=SC2086
ssh ${SCX_SSH_OPTS} "${HOST}" "mkdir -p \"${DEST}/benchmarks\" \"${DEST}/scripts/contabo\" \"${DEST}/contrib\" \"${DEST}/scripts/oneclick/results\""

# shellcheck disable=SC2086
scp ${SCX_SSH_OPTS} -r "${ROOT}/benchmarks/sched-ext-gates" "${HOST}:${DEST}/benchmarks/"
scp ${SCX_SSH_OPTS} -r "${ROOT}/benchmarks/ebpf-gates" "${HOST}:${DEST}/benchmarks/"
# shellcheck disable=SC2086
scp ${SCX_SSH_OPTS} "${ROOT}/scripts/contabo/sched-ext-vps-prep.sh" "${HOST}:${DEST}/scripts/contabo/"
scp ${SCX_SSH_OPTS} "${ROOT}/scripts/contabo/run-linux-ebpf-challenge-proof.sh" "${HOST}:${DEST}/scripts/contabo/"
scp ${SCX_SSH_OPTS} "${ROOT}/scripts/contabo/run-scx-1202-evidence.sh" "${HOST}:${DEST}/scripts/contabo/"
scp ${SCX_SSH_OPTS} "${ROOT}/scripts/verify-scx-1202-evidence.sh" "${HOST}:${DEST}/scripts/"
# shellcheck disable=SC2086
scp ${SCX_SSH_OPTS} "${ROOT}/scripts/contabo/apply-rt-watchdog-patch.sh" "${HOST}:${DEST}/scripts/contabo/"
# shellcheck disable=SC2086
scp ${SCX_SSH_OPTS} "${ROOT}/scripts/contabo/patch-sched-ext-makefile.py" "${HOST}:${DEST}/scripts/contabo/"
# shellcheck disable=SC2086
scp ${SCX_SSH_OPTS} "${ROOT}/scripts/contabo/submit-rt-guard-upstream.sh" "${HOST}:${DEST}/scripts/contabo/"
scp ${SCX_SSH_OPTS} "${ROOT}/scripts/contabo/tier2-ftrace-kernel.sh" "${HOST}:${DEST}/scripts/contabo/"
scp ${SCX_SSH_OPTS} "${ROOT}/scripts/contabo/patch-scx-ftrace-bypass.py" "${HOST}:${DEST}/scripts/contabo/"
# shellcheck disable=SC2086
scp ${SCX_SSH_OPTS} -r "${ROOT}/contrib/sched-ext" "${HOST}:${DEST}/contrib/"

# shellcheck disable=SC2086
ssh ${SCX_SSH_OPTS} "${HOST}" "chmod +x \"${DEST}/benchmarks/sched-ext-gates/\"*.sh \"${DEST}/benchmarks/ebpf-gates/\"*.sh \"${DEST}/scripts/contabo/\"*.sh"

echo "DEPLOY_OK ${HOST}:${DEST}"
