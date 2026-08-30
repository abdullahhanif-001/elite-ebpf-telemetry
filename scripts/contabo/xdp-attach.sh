#!/usr/bin/env bash
# xdp-attach.sh — load/unload xdp_mitigator via xdp-loader; PM2 guard before/after; auto SKIP.
set -euo pipefail

ACTION="${1:-status}"
IFACE="${ELITE_XDP_IFACE:-eth0}"
BUILD_ROOT="${ELITE_BUILD_ROOT:-/opt/elite-build}"
LOG_DIR="${ELITE_LOG_DIR:-${BUILD_ROOT}/logs}"
BPF_PIN="${ELITE_BPF_PIN:-/sys/fs/bpf/elite}"
POLICY_PIN="${ELITE_POLICY_PIN:-${BPF_PIN}/policy}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SRC="${ELITE_SRC:-/opt/elite/src}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="${LOG_DIR}/xdp-attach-${STAMP}.log"
PEER_LOCK="/tmp/vps-peer-agent.lock"

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG}") 2>&1

log() { echo "[xdp-attach] $*" >&2; }
skip() { log "SKIP: $*"; echo "XDP_ATTACH_SKIP" >>"${LOG}"; exit 2; }
die() { log "FAIL: $*"; exit 1; }

pm2_guard_wrap() {
  local when="$1" label="$2"
  local wrap="${SCRIPT_DIR}/pm2-guard-wrap.sh"
  if [[ ! -f "${wrap}" ]]; then
    wrap="${SRC}/scripts/contabo/pm2-guard-wrap.sh"
  fi
  if [[ -f /opt/elite/baseline/pm2-before.json ]] && command -v pm2 >/dev/null 2>&1; then
    [[ -f "${wrap}" ]] || die "pm2-guard-wrap.sh missing"
    bash "${wrap}" "${when}" "${label}" || die "PM2 guard failed at ${when}-${label}"
  else
    log "PM2 guard skipped (${when}-${label})"
  fi
}

resolve_bpf_src() {
  if [[ -f "${REPO_ROOT}/bpf/xdp_mitigator.c" ]]; then
    echo "${REPO_ROOT}/bpf"
    return
  fi
  if [[ -f "${SRC}/bpf/xdp_mitigator.c" ]]; then
    echo "${SRC}/bpf"
    return
  fi
  die "bpf/xdp_mitigator.c not found"
}

target_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo x86 ;;
    aarch64|arm64) echo arm64 ;;
    *) uname -m ;;
  esac
}

compile_obj() {
  local bpf_dir out_dir obj arch
  bpf_dir="$(resolve_bpf_src)"
  out_dir="${BUILD_ROOT}/out/bpf"
  obj="${out_dir}/xdp_mitigator.o"
  arch="$(target_arch)"
  mkdir -p "${out_dir}"
  command -v clang >/dev/null 2>&1 || skip "clang not installed"
  log "Compiling ${bpf_dir}/xdp_mitigator.c → ${obj}"
  clang -O2 -g -target bpf "-D__TARGET_ARCH_${arch}" \
    -I"${bpf_dir}/headers" -I"${bpf_dir}" \
    -c "${bpf_dir}/xdp_mitigator.c" -o "${obj}"
  echo "${obj}"
}

check_xdp_ready() {
  command -v xdp-loader >/dev/null 2>&1 || skip "xdp-tools not installed"
  command -v ethtool >/dev/null 2>&1 || skip "ethtool not installed"
  [[ -d "/sys/class/net/${IFACE}" ]] || skip "interface ${IFACE} not found"
  local driver
  driver="$(ethtool -i "${IFACE}" 2>/dev/null | awk '/^driver:/ {print $2; exit}' || true)"
  log "driver=${driver:-unknown} iface=${IFACE}"
  if [[ "${ELITE_XDP_FORCE:-0}" != "1" ]]; then
    case "${driver}" in
      virtio_net|veth|tap|dummy|bridge|"")
        skip "driver ${driver:-unknown} — set ELITE_XDP_FORCE=1"
        ;;
    esac
  fi
}

canonical_policy_pin() {
  mkdir -p "${BPF_PIN}"
  if [[ -e "${BPF_PIN}/elite_policy" && ! -e "${POLICY_PIN}" ]]; then
    if command -v bpftool >/dev/null 2>&1; then
      local id
      id="$(bpftool map show pinned "${BPF_PIN}/elite_policy" 2>/dev/null | awk '/^/ {print $1; exit}')"
      if [[ -n "${id}" ]]; then
        bpftool map pin id "${id}" "${POLICY_PIN}" 2>/dev/null || true
      fi
    fi
  fi
  if [[ ! -e "${POLICY_PIN}" ]] && command -v bpftool >/dev/null 2>&1; then
    local id
    # Prefer v3 map (80B value) when multiple elite_policy maps exist
    id="$(bpftool map show 2>/dev/null | awk -F: '/name elite_policy/ {gsub(/:/,"",$1); print $1}' | while read -r mid; do
      vsz=$(bpftool map show id "$mid" 2>/dev/null | awk '/value [0-9]+B/{print $2; exit}')
      echo "${vsz} ${mid}"
    done | sort -rn | head -1 | awk '{print $2}')"
    if [[ -n "${id}" ]]; then
      bpftool map pin id "${id}" "${POLICY_PIN}" 2>/dev/null || true
      log "pinned elite_policy id=${id} → ${POLICY_PIN}"
    fi
  fi
}

cmd_status() {
  log "=== xdp-attach status ${STAMP} iface=${IFACE} ==="
  command -v bpftool >/dev/null 2>&1 && bpftool net show dev "${IFACE}" 2>/dev/null || true
  if [[ -e "${POLICY_PIN}" ]]; then
    log "policy map pinned at ${POLICY_PIN}"
  elif [[ -e "${BPF_PIN}/elite_policy" ]]; then
    log "policy map pinned at ${BPF_PIN}/elite_policy"
  else
    log "policy map not pinned"
  fi
}

cmd_load() {
  [[ ! -f "${PEER_LOCK}" ]] || skip "peer lock ${PEER_LOCK}"
  check_xdp_ready
  pm2_guard_wrap before xdp-load

  local obj mode
  obj="$(compile_obj)"
  mode="${ELITE_XDP_MODE:-skb}"
  mkdir -p "${BPF_PIN}"

  log "xdp-loader load -m ${mode} -p ${BPF_PIN} ${IFACE} ${obj}"
  xdp-loader load -m "${mode}" -p "${BPF_PIN}" "${IFACE}" "${obj}"
  canonical_policy_pin
  # Safe default: actuate=0 until forecaster sets policy (ELITE_XDP_ACTUATE gate)
  if [[ -e "${POLICY_PIN}" ]] && command -v bpftool >/dev/null 2>&1; then
    bpftool map update pinned "${POLICY_PIN}" key hex 00 00 00 00 \
      value hex 03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 \
      00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 \
      00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 \
      00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 \
      00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 2>/dev/null || \
    bpftool map update pinned "${POLICY_PIN}" key hex 00 00 00 00 \
      value hex 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 \
      00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 \
      00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 2>/dev/null || true
    log "policy map actuate=0 default (forecaster enables actuate on sync)"
  fi
  if [[ -e "${BPF_PIN}/elite_xdp_stats" ]] && command -v bpftool >/dev/null 2>&1; then
    bpftool map pin pinned "${BPF_PIN}/elite_xdp_stats" "${BPF_PIN}/xdp_stats" 2>/dev/null || true
  fi
  if [[ -e "${BPF_PIN}/elite_lambda_ring" ]] && command -v bpftool >/dev/null 2>&1; then
    bpftool map pin pinned "${BPF_PIN}/elite_lambda_ring" "${BPF_PIN}/lambda_ring" 2>/dev/null || true
  fi
  if [[ -e "${BPF_PIN}/elite_devmap" ]] && command -v bpftool >/dev/null 2>&1; then
    bpftool map pin pinned "${BPF_PIN}/elite_devmap" "${BPF_PIN}/devmap" 2>/dev/null || true
  fi

  pm2_guard_wrap after xdp-load
  log "XDP_ATTACH_OK iface=${IFACE} pin=${BPF_PIN}"
  echo "XDP_ATTACH_OK" >"${LOG_DIR}/xdp-attach-latest.verdict"
}

cmd_unload() {
  command -v xdp-loader >/dev/null 2>&1 || skip "xdp-tools not installed"
  [[ -d "/sys/class/net/${IFACE}" ]] || skip "interface ${IFACE} not found"
  pm2_guard_wrap before xdp-unload
  xdp-loader unload "${IFACE}" || log "WARN: unload non-zero"
  pm2_guard_wrap after xdp-unload
  echo "XDP_UNLOAD_OK" >"${LOG_DIR}/xdp-attach-latest.verdict"
}

case "${ACTION}" in
  load) cmd_load ;;
  unload) cmd_unload ;;
  status) cmd_status ;;
  *) die "usage: $0 {load|unload|status}" ;;
esac
