#!/usr/bin/env bash
# install-updater-only.sh — surgical elite-updater install (no /opt/elite/scripts overwrite).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ELITE_ROOT="${ELITE_ROOT:-/opt/elite}"
UPDATER_BIN="${ELITE_UPDATER_BIN:-${ELITE_ROOT}/bin/elite-updater}"

log() { echo "[install-updater] $*"; }
die() { echo "[install-updater] FAIL: $*" >&2; exit 1; }

if [[ ! -x "${UPDATER_BIN}" ]]; then
  die "elite-updater not found at ${UPDATER_BIN} — build first"
fi

log "updater binary OK: ${UPDATER_BIN}"

for unit in elite-updater.service elite-updater.timer; do
  src="${REPO_ROOT}/deploy/contabo/${unit}"
  [[ -f "${src}" ]] || die "missing ${src}"
  install -m 0644 "${src}" "/etc/systemd/system/${unit}"
  log "installed /etc/systemd/system/${unit}"
done

if [[ -f "${REPO_ROOT}/deploy/contabo/update.yaml" ]]; then
  mkdir -p "${ELITE_ROOT}/config"
  install -m 0644 "${REPO_ROOT}/deploy/contabo/update.yaml" "${ELITE_ROOT}/config/update.yaml"
  log "installed ${ELITE_ROOT}/config/update.yaml (auto_apply should be false pre-push)"
elif [[ -f "${REPO_ROOT}/config/update.yaml" ]]; then
  mkdir -p "${ELITE_ROOT}/config"
  install -m 0644 "${REPO_ROOT}/config/update.yaml" "${ELITE_ROOT}/config/update.yaml"
fi

log "INSTALL_UPDATER_ONLY_OK"
