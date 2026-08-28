#!/usr/bin/env bash
# elite-vps-uninstall-safe.sh — remove ONLY Elite eBPF from Contabo/VPS.
# Absolute rules:
#   - Never pm2 stop|restart|delete|kill|reload|start
#   - Never touch peer agent paths/locks/sessions
#   - Abort on PM2 drift or peer footprint change
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${ELITE_UNINSTALL_OUT:-/tmp/elite-uninstall-$(date +%Y%m%d%H%M%S)}"
LOCK="/tmp/elite-uninstall.lock"
# Guard must live outside /opt/elite — purge deletes that tree.
GUARD="/tmp/elite-pm2-uninstall-guard.sh"
PEER_LOCKS=(/tmp/vps-peer-agent.lock /var/lock/elite-vps-peer.lock)

log() { echo "[elite-uninstall] $*"; }
die() { echo "[elite-uninstall] ABORT: $*" >&2; exit 1; }

need_root() {
  [[ "$(id -u)" -eq 0 ]] || die "must run as root"
}

need_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "Linux VPS required"
}

release_lock() {
  rm -f "${LOCK}"
}

cleanup_on_fail() {
  local ec=$?
  if [[ "${ec}" -ne 0 ]]; then
    log "FAILED exit=${ec} — left Elite stopped if already stopped; PM2 untouched; lock kept for inspection: ${LOCK}"
    log "artifacts: ${OUT}"
  fi
}

trap cleanup_on_fail EXIT

pm2_guard() {
  local label="$1"
  bash "${GUARD}" "${OUT}/pm2-before.json" "${label}" || die "PM2 guard failed at ${label}"
}

snap_peer() {
  local tag="$1"
  {
    for d in /opt/*; do
      [[ -e "${d}" ]] || continue
      name="$(basename "${d}")"
      [[ "${name}" == elite ]] && continue
      printf '%s\n' "${name}"
    done
  } | sort >"${OUT}/opt-non-elite-${tag}.txt" || true
  systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null \
    | awk '{print $1}' | sed 's/\.service$//' | grep -v '^elite' | sort \
    >"${OUT}/running-non-elite-${tag}.txt" || true
}

peer_guard() {
  local label="$1"
  snap_peer "cur-${label}"
  if ! diff -u "${OUT}/opt-non-elite-before.txt" "${OUT}/opt-non-elite-cur-${label}.txt" >"${OUT}/diff-opt-${label}.txt"; then
    cat "${OUT}/diff-opt-${label}.txt" >&2
    die "peer /opt footprint changed at ${label}"
  fi
  if ! diff -u "${OUT}/running-non-elite-before.txt" "${OUT}/running-non-elite-cur-${label}.txt" >"${OUT}/diff-units-${label}.txt"; then
    cat "${OUT}/diff-units-${label}.txt" >&2
    die "peer running units changed at ${label}"
  fi
  log "PEER_GUARD_OK[${label}]"
}

check_peer_locks() {
  local f
  for f in "${PEER_LOCKS[@]}"; do
    if [[ -f "${f}" ]]; then
      die "peer agent lock present: ${f} — wait until other agent finishes"
    fi
  done
}

find_oneclick() {
  if [[ -d /opt/elite/scripts/oneclick ]]; then
    echo /opt/elite/scripts/oneclick
  elif [[ -d /opt/elite/src/scripts/oneclick ]]; then
    echo /opt/elite/src/scripts/oneclick
  elif [[ -d "${SCRIPT_DIR}" ]]; then
    echo "${SCRIPT_DIR}"
  else
    echo ""
  fi
}

# --- Phase 0 ---
phase0() {
  need_root
  need_linux

  mkdir -p "${OUT}"
  check_peer_locks
  echo "$$ $(date -Is) elite-uninstall" >"${LOCK}"
  log "OUT=${OUT} LOCK=${LOCK}"

  # Guard must live outside /opt/elite — Phase 6 purge deletes that tree.
  local src_guard="${SCRIPT_DIR}/elite-pm2-uninstall-guard.sh"
  if [[ ! -f "${src_guard}" ]]; then
    src_guard="/tmp/elite-pm2-uninstall-guard.sh"
  fi
  [[ -f "${src_guard}" ]] || die "missing guard source: ${src_guard}"
  if [[ "$(readlink -f "${src_guard}" 2>/dev/null || realpath "${src_guard}" 2>/dev/null || echo "${src_guard}")" != \
        "$(readlink -f "${GUARD}" 2>/dev/null || realpath "${GUARD}" 2>/dev/null || echo "${GUARD}")" ]]; then
    cp -f "${src_guard}" "${GUARD}"
  fi
  chmod +x "${GUARD}"
  cp -f "${GUARD}" "${OUT}/elite-pm2-uninstall-guard.sh"

  command -v pm2 >/dev/null || die "pm2 not found"
  command -v python3 >/dev/null || die "python3 not found"
  command -v jq >/dev/null || die "jq not found"

  pm2 list | tee "${OUT}/pm2-before.txt"
  pm2 jlist >"${OUT}/pm2-before.json"
  jq -r '.[] | [.name, .pm2_env.status, .pm2_env.restart_time, .pid] | @tsv' \
    "${OUT}/pm2-before.json" | tee "${OUT}/pm2-before.tsv"

  local count
  count="$(jq 'length' "${OUT}/pm2-before.json")"
  log "PM2 app count=${count}"
  if [[ "${count}" -lt 1 ]]; then
    die "no PM2 apps found — refusing uninstall without baseline"
  fi

  # All must be online before we touch Elite
  if ! jq -e '[.[].pm2_env.status] | all(. == "online")' "${OUT}/pm2-before.json" >/dev/null; then
    die "not all PM2 apps online — fix PM2 first"
  fi

  pm2_guard baseline
  snap_peer before
  systemctl list-units 'elite*' --all --no-pager | tee "${OUT}/elite-units-before.txt" || true
  ss -lntp 2>/dev/null | grep -E '9102|9103|9104|9105|9435|2224' | tee "${OUT}/elite-ports-before.txt" || true
  log "Phase 0 complete"
}

# --- Phase 1 ---
phase1() {
  if [[ -f /sys/fs/cgroup/elite-dcic/be/cpu.max ]]; then
    echo max 100000 >/sys/fs/cgroup/elite-dcic/be/cpu.max
    log "Soft DCIC BE cpu.max fail-open"
  fi
  pm2_guard after-dcic-failopen
}

# --- Phase 2 ---
phase2() {
  systemctl disable --now elite-updater.timer 2>/dev/null || true
  systemctl disable --now elite-updater.service 2>/dev/null || true
  systemctl disable --now elite-agent.service 2>/dev/null || true
  systemctl disable --now elite-ecgf.service 2>/dev/null || true
  systemctl disable --now elite-dcic.service 2>/dev/null || true
  systemctl disable --now elite-llc-sensors.service 2>/dev/null || true
  systemctl disable --now elite-ig-metrics.service 2>/dev/null || true
  systemctl disable --now elite-ebpf-exporter.service 2>/dev/null || true
  systemctl disable --now elite-metrics-bridge.service 2>/dev/null || true
  pm2_guard after-stop
  peer_guard after-stop
}

# --- Phase 3 ---
phase3() {
  local OC s
  OC="$(find_oneclick)"
  log "oneclick dir=${OC:-none}"
  for s in elite-ecgf-pack.sh elite-soft-dcic-pack.sh elite-llc-pack.sh elite-physics-pack.sh; do
    if [[ -n "${OC}" && -f "${OC}/${s}" ]]; then
      log "uninstall ${s}"
      bash "${OC}/${s}" uninstall || true
    else
      log "skip ${s} (not found)"
    fi
    pm2_guard "after-${s}"
  done
  peer_guard after-packs
}

# --- Phase 4 ---
phase4() {
  if command -v docker >/dev/null 2>&1; then
    docker rm -f elite-prometheus elite-grafana 2>/dev/null || true
  fi
  pm2_guard after-docker
  peer_guard after-docker
}

# --- Phase 5 ---
phase5() {
  # Only remove Elite cron lines; preserve all other crontab entries
  if crontab -l >/tmp/elite-cron-before.txt 2>/dev/null; then
    grep -vE 'pm2-guard|/opt/elite|elite-agent' /tmp/elite-cron-before.txt >/tmp/elite-cron-after.txt || true
    crontab /tmp/elite-cron-after.txt || true
    log "crontab Elite lines stripped (if any)"
  fi
  rm -f /etc/systemd/system/elite-*.service \
        /etc/systemd/system/elite-*.timer \
        /etc/systemd/system/elite-*.path
  systemctl daemon-reload
  systemctl reset-failed 2>/dev/null || true
  pm2_guard after-cleanup
  peer_guard after-cleanup
}

# --- Phase 6 ---
phase6() {
  pm2_guard before-purge
  peer_guard before-purge
  rm -rf /opt/elite /etc/elite /var/lib/elite
  rm -f /usr/local/bin/elite-agent /usr/local/bin/elite-updater \
        /usr/local/bin/elite-dcic /usr/local/bin/elite-ecgf \
        /usr/local/bin/elite-llc-sensors /usr/local/bin/ig 2>/dev/null || true
  rmdir /sys/fs/cgroup/elite-dcic/be 2>/dev/null || true
  rmdir /sys/fs/cgroup/elite-dcic 2>/dev/null || true
  pm2_guard after-purge
  peer_guard after-purge
}

# --- Phase 7 ---
phase7() {
  pm2 list | tee "${OUT}/pm2-after.txt"
  pm2 jlist >"${OUT}/pm2-after.json"
  jq -r '.[] | [.name, .pm2_env.status, .pm2_env.restart_time, .pid] | @tsv' \
    "${OUT}/pm2-after.json" | tee "${OUT}/pm2-after.tsv"
  pm2_guard final
  peer_guard final
  systemctl list-units 'elite*' --all --no-pager | tee "${OUT}/elite-units-after.txt" || true
  ss -lntp 2>/dev/null | grep -E '9102|9103|9104|9105|9435|2224' | tee "${OUT}/elite-ports-after.txt" || echo "ports clear" | tee "${OUT}/elite-ports-after.txt"
  if [[ -d /opt/elite ]]; then
    die "/opt/elite still exists"
  fi
  echo OPT_ELITE_GONE | tee "${OUT}/verdict.txt"
  echo ELITE_UNINSTALL_PM2_SAFE | tee -a "${OUT}/verdict.txt"
  release_lock
  trap - EXIT
  log "DONE artifacts=${OUT}"
}

main() {
  phase0
  phase1
  phase2
  phase3
  phase4
  phase5
  phase6
  phase7
}

main "$@"
