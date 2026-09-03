#!/usr/bin/env bash
# Elite one-click orchestrator — profiled install / enable / disable / status / test.
# Physics/math/low-level core; heavy compose only via compose-* profiles.
# Usage:
#   bash scripts/oneclick/elite-oneclick.sh install --profile predict
#   bash scripts/oneclick/elite-oneclick.sh enable forecast
#   bash scripts/oneclick/elite-oneclick.sh status
#   bash scripts/oneclick/elite-oneclick.sh test --suite after-working
#   bash scripts/oneclick/elite-oneclick.sh test --suite heavy
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=versions.env
source "${SCRIPT_DIR}/versions.env"
# shellcheck source=profiles.env
source "${SCRIPT_DIR}/profiles.env"

STATE_JSON="${ELITE_ONECLICK_STATE:-/etc/elite/oneclick.json}"
CMD="${1:-status}"
shift || true

PROFILE=""
SUITE="after-working"
DRY_RUN=0
FEATURE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --suite) SUITE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *)
      if [[ -z "${FEATURE}" && "${CMD}" =~ ^(enable|disable)$ ]]; then
        FEATURE="$1"; shift
      else
        echo "Unknown arg: $1" >&2; exit 1
      fi
      ;;
  esac
done

log() { echo "[elite-oneclick] $*"; }

need_linux() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Linux VPS/Server target required (got $(uname -s))." >&2
    exit 1
  fi
}

profile_features() {
  local p="$1"
  local key="PROFILE_${p}"
  # shellcheck disable=SC2086
  eval "echo \${${key}:-}"
}

resolve_default_profile() {
  if [[ -f /etc/elite/soft-dcic-ready ]] || [[ -x /usr/local/bin/elite-dcic ]]; then
    echo "${DEFAULT_PROFILE_IF_DCIC}"
  else
    echo "${DEFAULT_PROFILE}"
  fi
}

write_state() {
  local profile="$1"
  shift
  local features=("$@")
  mkdir -p "$(dirname "${STATE_JSON}")"
  local feat_json
  feat_json="$(printf '%s\n' "${features[@]}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))' 2>/dev/null || echo '[]')"
  cat > "${STATE_JSON}" <<EOF
{
  "profile": "${profile}",
  "features": ${feat_json},
  "forecast_alpha": "${FORECAST_ALPHA}",
  "forecast_window": ${FORECAST_WINDOW},
  "hard_drop_seconds": ${HARD_DROP_SECONDS},
  "llc_enabled": "${LLC_ENABLED}",
  "dcic_mode": "${DCIC_MODE}",
  "actuate_track": "${ACTUATE_TRACK}",
  "cpu_quota_pct": ${CPU_QUOTA_PCT},
  "updated_at": "$(date -Is 2>/dev/null || date)"
}
EOF
  log "state -> ${STATE_JSON}"
}

read_features_from_state() {
  if [[ ! -f "${STATE_JSON}" ]]; then
    return 0
  fi
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ".join(d.get("features") or []))' "${STATE_JSON}" 2>/dev/null || true
}

has_feature() {
  local needle="$1"
  shift
  local f
  for f in "$@"; do
    [[ "${f}" == "${needle}" ]] && return 0
  done
  return 1
}

install_physics() {
  log "feature=physics"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN would run elite-physics-pack.sh install"
    return 0
  fi
  bash "${SCRIPT_DIR}/elite-physics-pack.sh" install
}

enable_forecast_knobs() {
  log "feature=forecast (enable pkg/forecaster in agent config.yaml)"
  mkdir -p /etc/elite /opt/elite/config /var/lib/elite
  cat > /etc/elite/forecast.env <<EOF
FORECAST_ENABLED=true
FORECAST_ALPHA=${FORECAST_ALPHA}
FORECAST_WINDOW=${FORECAST_WINDOW}
FORECAST_HORIZON=${FORECAST_HORIZON}
HARD_DROP_SECONDS=${HARD_DROP_SECONDS}
EOF
  log "wrote /etc/elite/forecast.env"
  local cfg="/opt/elite/config/config.yaml"
  if [[ -f "${cfg}" ]]; then
    python3 - <<PY
import pathlib, re
cfg = pathlib.Path("${cfg}")
text = cfg.read_text(encoding="utf-8")
block = """forecast:
  enabled: true
  interval: 1s
  horizon: ${FORECAST_HORIZON}
  window: ${FORECAST_WINDOW}
  alpha: ${FORECAST_ALPHA}
  hardDropSeconds: ${HARD_DROP_SECONDS}
  accThreshold: 0.001
  mode: dry-run
  semiCooldown: 60s
  llcURL: "http://127.0.0.1:9104/metrics"
  readPSI: true
  decisionPath: "/var/lib/elite/predict-decision.json"
  targets:
    - url: "http://127.0.0.1:9102/metrics"
      series: ["elite_socketlatency", "elite_softirq"]
"""
# Prefer native :9102 only. Optional :9435 when physics pack is healthy (avoid hang/deadlock).
if pathlib.Path("/opt/elite/physics-pack/bin/ebpf_exporter").exists():
    import urllib.request
    ok9435 = False
    try:
        with urllib.request.urlopen("http://127.0.0.1:9435/metrics", timeout=2) as r:
            ok9435 = r.status == 200
    except Exception:
        ok9435 = False
    if ok9435:
        block = block.replace(
            '  targets:\n    - url: "http://127.0.0.1:9102/metrics"',
            '  targets:\n    - url: "http://127.0.0.1:9435/metrics"\n      series: ["softirq_wait_seconds"]\n    - url: "http://127.0.0.1:9102/metrics"',
            1,
        )

if re.search(r"(?m)^forecast:\\s*$", text):
    text = re.sub(r"(?ms)^forecast:.*?(?=^(?:[a-zA-Z]|\\Z))", block, text, count=1)
else:
    # insert after otel block or at top after port
    if "otel:" in text:
        text = re.sub(r"(?ms)^(otel:.*?)(?=^[a-zA-Z])", r"\\1" + block, text, count=1)
    else:
        text = block + text
cfg.write_text(text, encoding="utf-8")
print("patched", cfg, "forecast.enabled=true")
PY
    if command -v systemctl >/dev/null && systemctl is-active --quiet elite-agent 2>/dev/null; then
      systemctl restart elite-agent
      log "restarted elite-agent for forecast"
    fi
  else
    log "WARN: ${cfg} missing — write deploy/server/config.yaml manually"
  fi
}

install_llc() {
  log "feature=llc"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN would install elite-llc-sensors"
    return 0
  fi
  if [[ -f "${SCRIPT_DIR}/elite-llc-pack.sh" ]]; then
    LLC_ENABLED="${LLC_ENABLED}" LLC_SAMPLE_PERIOD="${LLC_SAMPLE_PERIOD}" \
      bash "${SCRIPT_DIR}/elite-llc-pack.sh" install
  else
    log "llc pack not present yet — skip"
  fi
}

install_dcic() {
  log "feature=dcic"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN would run elite-soft-dcic-pack.sh install"
    return 0
  fi
  DCIC_MODE="${DCIC_MODE}" bash "${SCRIPT_DIR}/elite-soft-dcic-pack.sh" install
  bash "${SCRIPT_DIR}/dcic-capability-gate.sh" || true
}

install_ecgf() {
  log "feature=ecgf (ADR-005 ECGF-lite)"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN would run elite-ecgf-pack.sh install"
    return 0
  fi
  bash "${SCRIPT_DIR}/elite-ecgf-pack.sh" install
}

install_ig_note() {
  log "feature=ig — ensure Inspektor Gadget metrics from physics pack (observe only; not a process manager)"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  # Physics pack installs ig + elite-ig-metrics when available
  if systemctl list-unit-files elite-ig-metrics.service &>/dev/null; then
    systemctl enable --now elite-ig-metrics.service 2>/dev/null || true
    log "elite-ig-metrics enabled"
  else
    log "ig metrics unit not present yet — physics pack install creates it when IG_VERSION pin resolves"
  fi
}

install_compose_stub() {
  local name="$1"
  log "feature=${name} (optional compose — see scripts/oneclick/compose/${name}.md)"
  mkdir -p "${SCRIPT_DIR}/compose"
  if [[ ! -f "${SCRIPT_DIR}/compose/${name}.md" ]]; then
    cat > "${SCRIPT_DIR}/compose/${name}.md" <<EOF
# Optional compose: ${name}

Not installed by Server default. Pin upstream separately; keep CPUQuota low.
See ADR-003 / ADR-004. Enable with: elite-oneclick.sh enable ${name}
EOF
  fi
}

apply_features() {
  local profile="$1"
  shift
  local features=("$@")
  local f
  for f in "${features[@]}"; do
    case "${f}" in
      physics) install_physics ;;
      forecast) enable_forecast_knobs ;;
      llc) install_llc ;;
      dcic) install_dcic ;;
      ecgf) install_ecgf ;;
      ig) install_ig_note ;;
      netstacklat|obi|parca|kepler|sec) install_compose_stub "${f}" ;;
      *) log "unknown feature token: ${f}" ;;
    esac
  done
  write_state "${profile}" "${features[@]}"
}

cmd_install() {
  need_linux
  if [[ -z "${PROFILE}" ]]; then
    PROFILE="$(resolve_default_profile)"
  fi
  # normalize hyphen to underscore for PROFILE_* keys
  local key="${PROFILE//-/_}"
  local feats
  feats="$(profile_features "${key}")"
  if [[ -z "${feats// /}" && "${key}" != "minimal" ]]; then
    echo "Unknown profile: ${PROFILE} (try predict, closed-loop, physics, llc, dcic-soft, compose-ig)" >&2
    exit 1
  fi
  log "install profile=${PROFILE} features=[${feats}] dry_run=${DRY_RUN}"
  # shellcheck disable=SC2206
  local arr=(${feats})
  apply_features "${PROFILE}" "${arr[@]}"
  log "install complete"
}

cmd_enable() {
  need_linux
  if [[ -z "${FEATURE}" ]]; then
    echo "Usage: $0 enable <forecast|llc|dcic|ig|netstacklat|obi|parca|kepler|sec>" >&2
    exit 1
  fi
  local cur
  cur="$(read_features_from_state)"
  # shellcheck disable=SC2206
  local arr=(${cur})
  if ! has_feature "${FEATURE}" "${arr[@]}"; then
    arr+=("${FEATURE}")
  fi
  local profile="custom"
  [[ -f "${STATE_JSON}" ]] && profile="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("profile","custom"))' "${STATE_JSON}" 2>/dev/null || echo custom)"
  apply_features "${profile}" "${arr[@]}"
}

cmd_disable() {
  need_linux
  if [[ -z "${FEATURE}" ]]; then
    echo "Usage: $0 disable <feature>" >&2
    exit 1
  fi
  local cur
  cur="$(read_features_from_state)"
  # shellcheck disable=SC2206
  local old=(${cur})
  local new=()
  local f
  for f in "${old[@]}"; do
    [[ "${f}" == "${FEATURE}" ]] && continue
    new+=("${f}")
  done
  local profile="custom"
  [[ -f "${STATE_JSON}" ]] && profile="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("profile","custom"))' "${STATE_JSON}" 2>/dev/null || echo custom)"
  write_state "${profile}" "${new[@]}"
  log "disabled ${FEATURE} (units left installed; stop manually if needed)"
}

cmd_status() {
  echo "=== Elite one-click status ==="
  echo "repo=${REPO_ROOT}"
  if [[ -f "${STATE_JSON}" ]]; then
    cat "${STATE_JSON}"
  else
    echo "no state at ${STATE_JSON} (default profile would be $(resolve_default_profile))"
  fi
  if [[ -f "${SCRIPT_DIR}/elite-physics-pack.sh" ]]; then
    bash "${SCRIPT_DIR}/elite-physics-pack.sh" status 2>/dev/null || true
  fi
  if [[ -f "${SCRIPT_DIR}/elite-soft-dcic-pack.sh" ]]; then
    bash "${SCRIPT_DIR}/elite-soft-dcic-pack.sh" status 2>/dev/null || true
  fi
}

cmd_test() {
  case "${SUITE}" in
    after-working)
      bash "${SCRIPT_DIR}/after-working.sh"
      ;;
    heavy)
      bash "${SCRIPT_DIR}/heavy-engineer-suite.sh"
      ;;
    *)
      echo "Unknown suite: ${SUITE}" >&2
      exit 1
      ;;
  esac
}

case "${CMD}" in
  install) cmd_install ;;
  enable) cmd_enable ;;
  disable) cmd_disable ;;
  status) cmd_status ;;
  test) cmd_test ;;
  *)
    cat <<EOF
Usage:
  $0 install --profile <minimal|physics|predict|llc|dcic-soft|closed-loop|ecgf|full|compose-*>
  $0 install --profile full --dry-run
  $0 enable|disable <feature>
  $0 status
  $0 test --suite after-working
  $0 test --suite heavy
EOF
    exit 1
    ;;
esac
