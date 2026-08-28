#!/usr/bin/env bash
# vps-disk-clean-keep-one.sh — Contabo disk clean; keep ONLY newest xerosphere hourly backup.
# Absolute: never pm2 stop/restart/delete/kill. Abort on PM2 drift.
# Usage: bash vps-disk-clean-keep-one.sh --force
# Prerequisite: Contabo panel snapshot already created (user-confirmed).
set -euo pipefail

FORCE="${1:-}"
if [[ "${FORCE}" != "--force" ]]; then
  echo "Refusing without --force. Usage: $0 --force" >&2
  echo "Confirm Contabo panel snapshot exists first." >&2
  exit 2
fi

[[ "$(id -u)" -eq 0 ]] || { echo "must be root" >&2; exit 1; }
[[ "$(uname -s)" == "Linux" ]] || { echo "Linux VPS only" >&2; exit 1; }

OUT="${VPS_DISK_CLEAN_OUT:-/tmp/vps-disk-clean-$(date +%Y%m%d%H%M%S)}"
BK="${BACKUP_DIR:-/root/.xerosphere_backups}"
GUARD="/tmp/elite-pm2-uninstall-guard.sh"
PEER_LOCKS=(/tmp/vps-peer-agent.lock /var/lock/elite-vps-peer.lock)

log() { echo "[vps-disk-clean] $*"; }
die() { echo "[vps-disk-clean] ABORT: $*" >&2; exit 1; }

mkdir -p "${OUT}"
log "OUT=${OUT}"

for f in "${PEER_LOCKS[@]}"; do
  [[ -f "${f}" ]] && die "peer agent lock present: ${f}"
done

command -v pm2 >/dev/null || die "pm2 not found"
command -v python3 >/dev/null || die "python3 not found"
[[ -f "${GUARD}" ]] || die "missing ${GUARD} — scp elite-pm2-uninstall-guard.sh to /tmp first"

pm2_guard() {
  bash "${GUARD}" "${OUT}/pm2-before.json" "$1" || die "PM2 guard failed at $1"
}

df -h / | tee "${OUT}/df-before.txt"
pm2 list | tee "${OUT}/pm2-before.txt"
pm2 jlist >"${OUT}/pm2-before.json"

if ! jq -e '[.[].pm2_env.status] | all(. == "online")' "${OUT}/pm2-before.json" >/dev/null; then
  die "not all PM2 apps online — fix PM2 first"
fi
COUNT="$(jq 'length' "${OUT}/pm2-before.json")"
[[ "${COUNT}" -ge 1 ]] || die "no PM2 apps"
log "PM2 apps=${COUNT}"
pm2_guard disk-clean-baseline

# --- Keep only newest hourly .db.gz ---
mkdir -p "${BK}"
ls -la "${BK}" | tee "${OUT}/backups-before.txt"

LATEST=""
if ls -1t "${BK}"/xerosphere_hourly_*.db.gz >/dev/null 2>&1; then
  LATEST="$(ls -1t "${BK}"/xerosphere_hourly_*.db.gz | head -1)"
fi
if [[ -z "${LATEST}" || ! -f "${LATEST}" ]]; then
  die "no xerosphere_hourly_*.db.gz found under ${BK} — refusing to wipe blindly"
fi
log "KEEP_LATEST=${LATEST}"
echo "${LATEST}" >"${OUT}/kept-backup.txt"

# Delete older hourlies
while IFS= read -r f; do
  [[ -z "${f}" ]] && continue
  [[ "${f}" == "${LATEST}" ]] && continue
  log "rm hourly ${f}"
  rm -f "${f}"
done < <(ls -1t "${BK}"/xerosphere_hourly_*.db.gz 2>/dev/null || true)

# Delete temp DB copies / journals
find "${BK}" -maxdepth 1 -type f \( -name 'temp_*.db' -o -name 'temp_*.db-journal' \) -print -delete \
  | tee "${OUT}/temp-deleted.txt" || true

# Safety: ensure latest still exists
[[ -f "${LATEST}" ]] || die "LATEST backup vanished after cleanup"
LEFT="$(find "${BK}" -maxdepth 1 -type f -name 'xerosphere_hourly_*.db.gz' | wc -l)"
[[ "${LEFT}" -eq 1 ]] || die "expected exactly 1 hourly backup, found ${LEFT}"
pm2_guard after-backup-prune

# --- Safe junk ---
journalctl --vacuum-size=50M 2>/dev/null || true
apt-get clean 2>/dev/null || true
rm -f /var/cache/apt/archives/*.deb 2>/dev/null || true

# Truncate bulky app logs only (keep files / inodes)
find /var/www -type f -path '*/logs/*.log' -size +5M -exec truncate -s 0 {} \; 2>/dev/null || true

# Known deploy tarballs only
rm -f /var/www/xero-sphere-ai.com/dist-ui-linux.tgz \
      /var/www/xero-sphere-ai.com/*.tgz 2>/dev/null || true

# /tmp junk older than 2 days — never remove peer/uninstall locks
find /tmp -type f -mtime +2 \
  ! -name 'vps-peer-agent.lock' \
  ! -name 'elite-uninstall.lock' \
  ! -name 'elite-pm2-uninstall-guard.sh' \
  ! -name 'xtax-rates.lock' \
  -delete 2>/dev/null || true

pm2_guard after-junk

# Docker unused only (active container image retained)
if command -v docker >/dev/null 2>&1; then
  docker ps --format '{{.ID}} {{.Image}} {{.Status}}' | tee "${OUT}/docker-ps-before.txt" || true
  docker image prune -f 2>/dev/null || true
  docker builder prune -f 2>/dev/null || true
  # Remove images not used by any container
  docker image prune -af 2>/dev/null || true
  docker ps --format '{{.ID}} {{.Image}} {{.Status}}' | tee "${OUT}/docker-ps-after.txt" || true
fi
pm2_guard after-docker

# --- Final ---
df -h / | tee "${OUT}/df-after.txt"
pm2 list | tee "${OUT}/pm2-after.txt"
pm2_guard disk-clean-final
ls -la "${BK}" | tee "${OUT}/backups-after.txt"
echo "KEPT=$(cat "${OUT}/kept-backup.txt")"
echo "HOURLY_COUNT=${LEFT}"
echo VPS_DISK_CLEAN_PM2_SAFE | tee "${OUT}/verdict.txt"
log "DONE artifacts=${OUT}"
