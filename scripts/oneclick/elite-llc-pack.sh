#!/usr/bin/env bash
# Elite LLC sensors pack — PERF cache-references/misses → :9104
# Usage: bash scripts/oneclick/elite-llc-pack.sh install|status|uninstall
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=versions.env
source "${SCRIPT_DIR}/versions.env"
# shellcheck source=profiles.env
source "${SCRIPT_DIR}/profiles.env" 2>/dev/null || true

CMD="${1:-install}"
LLC_ROOT="/opt/elite/llc"
LISTEN="127.0.0.1:9104"
MODE="${LLC_ENABLED:-auto}"
PERIOD="${LLC_SAMPLE_PERIOD:-10000}"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
  fi
}

log() { echo "[elite-llc-pack] $*"; }

ensure_go() {
  if command -v go >/dev/null 2>&1; then
    return 0
  fi
  log "Installing Go 1.22.12..."
  local tar="go1.22.12.linux-amd64.tar.gz"
  curl -fsSL --proto '=https' --tlsv1.2 -o "/tmp/${tar}" "https://go.dev/dl/${tar}"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "/tmp/${tar}"
  ln -sfn /usr/local/go/bin/go /usr/local/bin/go
}

build_sensors() {
  ensure_go
  mkdir -p "${LLC_ROOT}/bin" /etc/elite
  (
    cd "${REPO_ROOT}"
    CGO_ENABLED=0 go build -o "${LLC_ROOT}/bin/elite-llc-sensors" ./cmd/elite-llc-sensors
  )
  install -m 0755 "${LLC_ROOT}/bin/elite-llc-sensors" /usr/local/bin/elite-llc-sensors
}

install_unit() {
  cat > /etc/systemd/system/elite-llc-sensors.service <<EOF
[Unit]
Description=Elite LLC PERF sensors
After=network.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/local/bin/elite-llc-sensors -listen ${LISTEN} -llc ${MODE} -sample-period ${PERIOD}
Restart=on-failure
RestartSec=3
CPUQuota=${CPU_QUOTA_PCT:-5}%
MemoryMax=64M
NoNewPrivileges=true
# perf may need CAP_PERFMON / CAP_SYS_ADMIN on some kernels
AmbientCapabilities=CAP_PERFMON CAP_SYS_ADMIN
CapabilityBoundingSet=CAP_PERFMON CAP_SYS_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now elite-llc-sensors.service
}

# Extend capability JSON with pmu / llc_sampling hints
patch_capability() {
  bash "${SCRIPT_DIR}/dcic-capability-gate.sh" || true
  local cap="/etc/elite/dcic-capability.json"
  [[ -f "${cap}" ]] || return 0
  python3 - <<'PY' || true
import json, os, subprocess
p="/etc/elite/dcic-capability.json"
d=json.load(open(p))
# probe perf
ok=False
try:
  r=subprocess.run(["perf","stat","-e","cache-references","--","true"],capture_output=True,timeout=5)
  ok=(r.returncode==0)
except Exception:
  ok=False
d["pmu"]=ok
d["llc_sampling"]=ok
d["llc_listen"]="127.0.0.1:9104"
json.dump(d, open(p,"w"), indent=2)
print("capability patched pmu=", ok)
PY
}

do_install() {
  need_root
  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Linux only" >&2
    exit 1
  fi
  build_sensors
  install_unit
  patch_capability
  log "LLC sensors on ${LISTEN} mode=${MODE}"
}

do_status() {
  systemctl is-active elite-llc-sensors.service 2>/dev/null || echo "elite-llc-sensors: inactive"
  curl -s --connect-timeout 1 "${LISTEN}/metrics" 2>/dev/null | head -n 20 || echo "metrics unreachable"
}

do_uninstall() {
  need_root
  systemctl disable --now elite-llc-sensors.service 2>/dev/null || true
  rm -f /etc/systemd/system/elite-llc-sensors.service
  systemctl daemon-reload
  rm -rf "${LLC_ROOT}"
  rm -f /usr/local/bin/elite-llc-sensors
}

case "${CMD}" in
  install) do_install ;;
  status) do_status ;;
  uninstall) do_uninstall ;;
  *) echo "Usage: $0 {install|status|uninstall}" >&2; exit 1 ;;
esac
