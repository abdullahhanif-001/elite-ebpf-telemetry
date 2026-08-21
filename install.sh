#!/usr/bin/env bash
# Elite eBPF — one-click installer (Kubernetes or bare-metal)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MODE=""
DRY_RUN=false

usage() {
  cat <<EOF
Elite eBPF Agent — one-click install

Usage:
  ./install.sh              Auto-detect environment and install
  ./install.sh --mode k8s     Force Kubernetes bundle
  ./install.sh --mode metal   Bare-metal / VPS (systemd) instructions
  ./install.sh --dry-run      Print actions without applying

Requires:
  k8s:  kubectl + reachable cluster, Linux nodes with BTF
  metal: Linux, systemd, root, kernel 5.8+ with BTF
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

detect_k8s() {
  command -v kubectl &>/dev/null || return 1
  kubectl cluster-info &>/dev/null 2>&1
}

detect_metal() {
  [[ "$(uname -s)" == "Linux" ]] && command -v systemctl &>/dev/null
}

apply_k8s() {
  echo "== Installing Elite on Kubernetes =="
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
  echo "== Bare-metal / VPS install (systemd) =="
  echo ""
  echo "Copy deploy files to the host:"
  echo "  sudo mkdir -p /opt/elite/{bin,config,btf,scripts,baseline,logs}"
  echo "  sudo cp -r $ROOT/deploy/contabo/* /opt/elite/"
  echo ""
  echo "Build or pull agent binary, then:"
  echo "  sudo cp deploy/contabo/config.yaml /opt/elite/config/"
  echo "  sudo cp deploy/contabo/elite-agent.service /etc/systemd/system/"
  echo "  sudo cp deploy/contabo/pm2-guard.sh /opt/elite/scripts/"
  echo "  sudo cp /sys/kernel/btf/vmlinux /opt/elite/btf/vmlinux"
  echo "  sudo systemctl daemon-reload && sudo systemctl enable --now elite-agent"
  echo ""
  echo "Verify:"
  echo "  curl http://127.0.0.1:9102/metrics"
  echo "  bash /opt/elite/scripts/pm2-guard.sh   # if PM2 apps present"
  echo ""
  echo "Optional — Elite One-Click Physics Pack (OSS exporters, no scratch BPF):"
  echo "  sudo bash $ROOT/scripts/oneclick/elite-physics-pack.sh install"
  echo "  bash $ROOT/scripts/oneclick/physics-pack-proof.sh"
  echo ""
  echo "See deploy/contabo/ROLLBACK.md for instant rollback."
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
