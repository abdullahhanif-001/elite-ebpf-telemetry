#!/usr/bin/env bash
# pm2-guard-wrap.sh — run strict PM2 guards before/after each phase; abort on drift.
set -euo pipefail

WHEN="${1:?usage: $0 before|after <phase-name>}"
LABEL="${2:?usage: $0 before|after <phase-name>}"
BASE="/opt/elite/baseline/pm2-before.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "PM2_WRAP ${WHEN} ${LABEL}"

if [[ ! -f "${BASE}" ]]; then
  echo "FAIL: PM2 baseline missing: ${BASE}" >&2
  exit 1
fi

bash "${REPO_ROOT}/scripts/oneclick/elite-pm2-uninstall-guard.sh" "${BASE}" "${WHEN}-${LABEL}"
bash "${REPO_ROOT}/deploy/contabo/pm2-guard.sh"

echo "PM2_WRAP_OK ${WHEN} ${LABEL}"
