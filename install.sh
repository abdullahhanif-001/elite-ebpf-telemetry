#!/usr/bin/env bash
# Elite eBPF — one-click installer (Kubernetes or bare-metal)
# Metal path: preflight → layout → download/copy signed agent → systemd → optional profile.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MODE=""
DRY_RUN=false
PROFILE=""
CHANNEL="${ELITE_CHANNEL:-stable}"
REPO="${ELITE_REPO:-abdullahhanif-001/elite-ebpf-telemetry}"
ELITE_ROOT="${ELITE_ROOT:-/opt/elite}"
VERSION="${ELITE_VERSION:-latest}"
SKIP_UPDATER=false
SKIP_PROFILE=false

usage() {
  cat <<EOF
Elite eBPF Agent — one-click install

Usage:
  ./install.sh                          Auto-detect and install
  ./install.sh --mode k8s               Kubernetes bundle
  ./install.sh --mode metal             Bare-metal / VPS (systemd) — executes install
  ./install.sh --profile physics        Metal: install packs via elite-oneclick
  ./install.sh --profile full           Metal: agent + physics + forecast + llc + dcic + ecgf + ig
  ./install.sh --version v1.2.3         Pin GitHub release tag (default: latest)
  ./install.sh --dry-run                Print actions without applying
  ./install.sh --skip-updater           Do not enable elite-updater.timer
  ./install.sh --skip-profile           Agent only (no oneclick packs)

Remote:
  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh \\
    | sudo bash -s -- --mode metal --profile physics

Requires:
  k8s:  kubectl + reachable cluster, Linux nodes with BTF
  metal: Linux, systemd, root, kernel 5.8+ with BTF
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --channel) CHANNEL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --skip-updater) SKIP_UPDATER=true; shift ;;
    --skip-profile) SKIP_PROFILE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

log() { echo "[elite-install] $*"; }
die() { echo "[elite-install] ERROR: $*" >&2; exit 1; }

detect_k8s() {
  command -v kubectl &>/dev/null || return 1
  kubectl cluster-info &>/dev/null 2>&1
}

detect_metal() {
  [[ "$(uname -s)" == "Linux" ]] && command -v systemctl &>/dev/null
}

kernel_ok() {
  local maj min
  maj="$(uname -r | cut -d. -f1)"
  min="$(uname -r | cut -d. -f2)"
  [[ "${maj}" -gt 5 ]] || { [[ "${maj}" -eq 5 ]] && [[ "${min}" -ge 8 ]]; }
}

preflight_metal() {
  [[ "$(id -u)" -eq 0 ]] || die "metal install requires root (sudo)"
  [[ "$(uname -s)" == "Linux" ]] || die "Linux required (got $(uname -s))"
  command -v systemctl >/dev/null || die "systemd required"
  kernel_ok || die "kernel 5.8+ required (got $(uname -r))"
  [[ -r /sys/kernel/btf/vmlinux ]] || die "BTF missing at /sys/kernel/btf/vmlinux — install linux-image with BTF or fail closed"
  command -v curl >/dev/null || die "curl required"
}

arch_name() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) die "unsupported arch $(uname -m)" ;;
  esac
}

# Prefer HTTPS-only transfers (Sonar shell:S6506).
CURL_TLS=(curl --proto "=https" --tlsv1.2 -fsSL)

resolve_release_tag() {
  if [[ "${VERSION}" != "latest" ]]; then
    echo "${VERSION}"
    return 0
  fi
  local tag
  tag="$("${CURL_TLS[@]}" -H 'Accept: application/vnd.github+json' -H 'User-Agent: elite-install' \
    "https://api.github.com/repos/${REPO}/releases/latest" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name") or "")' 2>/dev/null || true)"
  [[ -n "${tag}" ]] || die "could not resolve latest GitHub release for ${REPO}"
  echo "${tag}"
}

download_asset() {
  local tag="$1" name="$2" dest="$3"
  local url="https://github.com/${REPO}/releases/download/${tag}/${name}"
  log "download ${url}"
  if $DRY_RUN; then
    echo "DRY-RUN: ${CURL_TLS[*]} ${url} -o ${dest}"
    return 0
  fi
  if ! "${CURL_TLS[@]}" -H 'User-Agent: elite-install' "${url}" -o "${dest}"; then
    return 1
  fi
  chmod 0750 "${dest}"
}

verify_sha_if_present() {
  local tag="$1" asset="$2" bin="$3"
  local tmp
  tmp="$(mktemp)"
  if download_asset "${tag}" "SHA256SUMS" "${tmp}" 2>/dev/null; then
    local want got
    want="$(awk -v a="${asset}" '$2==a || $2==("./" a) {print $1; exit}' "${tmp}")"
    if [[ -n "${want}" ]]; then
      got="$(sha256sum "${bin}" | awk '{print $1}')"
      [[ "${got}" == "${want}" ]] || die "SHA256 mismatch for ${asset}"
      log "SHA256 OK for ${asset}"
    fi
  fi
  rm -f "${tmp}"
}

install_agent_binary() {
  local tag arch dest candidates c
  arch="$(arch_name)"
  dest="${ELITE_ROOT}/bin/elite-agent"
  mkdir -p "${ELITE_ROOT}/bin" "${ELITE_ROOT}/bin/previous"

  # Prefer local build / env override (dev and Contabo source trees)
  if [[ -n "${ELITE_AGENT_BIN:-}" && -x "${ELITE_AGENT_BIN}" ]]; then
    log "using ELITE_AGENT_BIN=${ELITE_AGENT_BIN}"
    $DRY_RUN || cp -f "${ELITE_AGENT_BIN}" "${dest}"
    return 0
  fi
  if [[ -x "${ROOT}/bin/elite-agent" ]]; then
    log "using local ${ROOT}/bin/elite-agent"
    $DRY_RUN || cp -f "${ROOT}/bin/elite-agent" "${dest}"
    return 0
  fi

  tag="$(resolve_release_tag)"
  candidates=("elite-agent.linux-${arch}" "elite-agent")
  for c in "${candidates[@]}"; do
    if download_asset "${tag}" "${c}" "${dest}.partial" 2>/dev/null; then
      verify_sha_if_present "${tag}" "${c}" "${dest}.partial"
      $DRY_RUN || mv -f "${dest}.partial" "${dest}"
      echo "${tag}" > "${ELITE_ROOT}/bin/.installed-version" 2>/dev/null || true
      log "installed elite-agent from ${tag}/${c}"
      return 0
    fi
  done

  # Last resort: build from this checkout
  if [[ -f "${ROOT}/Makefile" ]] && command -v go >/dev/null; then
    log "no release asset; building from source"
    if $DRY_RUN; then
      echo "DRY-RUN: make -C ${ROOT} build-elite-agent"
      return 0
    fi
    make -C "${ROOT}" build-elite-agent
    cp -f "${ROOT}/bin/elite-agent" "${dest}"
    return 0
  fi
  die "could not obtain elite-agent (no release asset, no local bin, no go build)"
}

install_updater_binary() {
  local tag arch dest
  arch="$(arch_name)"
  dest="${ELITE_ROOT}/bin/elite-updater"
  if [[ -x "${ROOT}/bin/elite-updater" ]]; then
    $DRY_RUN || cp -f "${ROOT}/bin/elite-updater" "${dest}"
    return 0
  fi
  if [[ -n "${ELITE_UPDATER_BIN:-}" && -x "${ELITE_UPDATER_BIN}" ]]; then
    $DRY_RUN || cp -f "${ELITE_UPDATER_BIN}" "${dest}"
    return 0
  fi
  tag="$(resolve_release_tag)" || return 0
  if download_asset "${tag}" "elite-updater.linux-${arch}" "${dest}.partial" 2>/dev/null \
    || download_asset "${tag}" "elite-updater" "${dest}.partial" 2>/dev/null; then
    $DRY_RUN || mv -f "${dest}.partial" "${dest}"
    log "installed elite-updater"
    return 0
  fi
  if [[ -f "${ROOT}/Makefile" ]] && command -v go >/dev/null; then
    $DRY_RUN || { make -C "${ROOT}" build-elite-updater && cp -f "${ROOT}/bin/elite-updater" "${dest}"; }
  else
    log "WARN: elite-updater not available; skip auto-update timer"
    return 1
  fi
}

apply_k8s() {
  log "Installing Elite on Kubernetes"
  if $DRY_RUN; then
    echo "DRY-RUN: kubectl apply -f $ROOT/deploy/elite-bundle.yaml"
    return 0
  fi
  kubectl apply -f "$ROOT/deploy/elite-bundle.yaml"
  echo ""
  echo "Done. Wait for DaemonSet:"
  echo "  kubectl rollout status daemonset/elite-agent -n elite"
  echo "  kubectl port-forward -n elite svc/elite-agent 9102:9102"
  echo "  curl http://127.0.0.1:9102/metrics"
}

apply_metal() {
  log "Bare-metal / VPS install (systemd) channel=${CHANNEL}"
  preflight_metal

  if $DRY_RUN; then
    log "DRY-RUN: would layout ${ELITE_ROOT}, install agent, enable systemd"
    [[ -n "${PROFILE}" ]] && log "DRY-RUN: would run elite-oneclick --profile ${PROFILE}"
    return 0
  fi

  mkdir -p "${ELITE_ROOT}"/{bin,config,btf,scripts,baseline,logs,scripts/oneclick}
  mkdir -p /var/lib/elite /etc/elite

  # Deploy configs and units from checkout when present
  if [[ -d "${ROOT}/deploy/contabo" ]]; then
    cp -f "${ROOT}/deploy/contabo/config.yaml" "${ELITE_ROOT}/config/config.yaml"
    cp -f "${ROOT}/deploy/contabo/elite-agent.service" /etc/systemd/system/elite-agent.service
    cp -f "${ROOT}/deploy/contabo/pm2-guard.sh" "${ELITE_ROOT}/scripts/pm2-guard.sh"
    chmod 0755 "${ELITE_ROOT}/scripts/pm2-guard.sh"
    if [[ -f "${ROOT}/deploy/contabo/elite-updater.service" ]]; then
      cp -f "${ROOT}/deploy/contabo/elite-updater.service" /etc/systemd/system/elite-updater.service
      cp -f "${ROOT}/deploy/contabo/elite-updater.timer" /etc/systemd/system/elite-updater.timer
    fi
  fi
  if [[ -f "${ROOT}/config/update.yaml" ]]; then
    cp -f "${ROOT}/config/update.yaml" "${ELITE_ROOT}/config/update.yaml"
  fi
  if [[ -d "${ROOT}/scripts/oneclick" ]]; then
    cp -a "${ROOT}/scripts/oneclick/." "${ELITE_ROOT}/scripts/oneclick/"
  fi

  # BTF cache for agent ExecStartPre
  cp -f /sys/kernel/btf/vmlinux "${ELITE_ROOT}/btf/vmlinux" 2>/dev/null || true

  install_agent_binary
  install_updater_binary || true

  systemctl daemon-reload
  systemctl enable --now elite-agent
  log "elite-agent enabled"

  if [[ "${SKIP_UPDATER}" != "true" ]] && [[ -x "${ELITE_ROOT}/bin/elite-updater" ]] \
    && [[ -f /etc/systemd/system/elite-updater.timer ]]; then
    systemctl enable --now elite-updater.timer
    log "elite-updater.timer enabled"
  fi

  # Wait for metrics
  local n=0
  while [[ "${n}" -lt 30 ]]; do
    n=$((n + 1))
    if curl -fsS "http://127.0.0.1:9102/metrics" 2>/dev/null | grep -q 'elite_'; then
      log "metrics OK on :9102"
      break
    fi
    sleep 2
  done

  if [[ "${SKIP_PROFILE}" != "true" ]]; then
    local p="${PROFILE}"
    if [[ -z "${p}" ]]; then
      p="full"
    fi
    if [[ -x "${ROOT}/scripts/oneclick/elite-oneclick.sh" ]]; then
      log "oneclick profile=${p}"
      bash "${ROOT}/scripts/oneclick/elite-oneclick.sh" install --profile "${p}"
    elif [[ -x "${ELITE_ROOT}/scripts/oneclick/elite-oneclick.sh" ]]; then
      bash "${ELITE_ROOT}/scripts/oneclick/elite-oneclick.sh" install --profile "${p}"
    else
      log "WARN: elite-oneclick.sh not found; agent-only install"
    fi
  fi

  echo ""
  echo "Done."
  echo "  curl http://127.0.0.1:9102/metrics"
  echo "  bash ${ELITE_ROOT}/scripts/pm2-guard.sh   # if PM2 apps present"
  echo "  systemctl status elite-agent elite-updater.timer"
  echo "See deploy/contabo/ROLLBACK.md for rollback."
}

if [[ -z "$MODE" ]]; then
  if detect_k8s; then
    MODE="k8s"
  elif detect_metal; then
    MODE="metal"
  else
    echo "Could not detect Kubernetes or Linux/systemd environment." >&2
    usage
    exit 1
  fi
fi

case "$MODE" in
  k8s|kubernetes) apply_k8s ;;
  metal|systemd|bare-metal) apply_metal ;;
  *) echo "Unknown mode: $MODE" >&2; exit 1 ;;
esac
