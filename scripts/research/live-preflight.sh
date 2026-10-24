#!/usr/bin/env bash
# live-preflight.sh — JSON fingerprint of THIS host (research claims must match).
set -euo pipefail
# shellcheck source=scripts/research/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

research_real_only_gate

ROOT="$(research_repo_root)"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
OUT="${RESEARCH_PREFLIGHT_OUT:-${RESEARCH_LEDGER_DIR}/preflight/live-${STAMP}.json}"
mkdir -p "$(dirname "${OUT}")"

export RESEARCH_PREFLIGHT_KERNEL RESEARCH_PREFLIGHT_HOST
RESEARCH_PREFLIGHT_KERNEL="$(uname -r)"
RESEARCH_PREFLIGHT_HOST="$(hostname 2>/dev/null || echo unknown)"
cfg="/boot/config-${RESEARCH_PREFLIGHT_KERNEL}"

export RESEARCH_HAS_SCHED_EXT=false
export RESEARCH_HAS_BTF=false
export RESEARCH_HAS_BPF_SYSCALL=false
export RESEARCH_HAS_KVM_GUEST=false

[[ -f /sys/kernel/btf/vmlinux ]] && RESEARCH_HAS_BTF=true
if [[ -f "${cfg}" ]]; then
  grep -q '^CONFIG_SCHED_CLASS_EXT=y' "${cfg}" 2>/dev/null && RESEARCH_HAS_SCHED_EXT=true
  grep -q '^CONFIG_BPF_SYSCALL=y' "${cfg}" 2>/dev/null && RESEARCH_HAS_BPF_SYSCALL=true
fi
# Cloud/kvm images often omit /boot/config-* — infer from runtime
[[ -d /sys/fs/bpf ]] && RESEARCH_HAS_BPF_SYSCALL=true
grep -qw hypervisor /proc/cpuinfo 2>/dev/null && RESEARCH_HAS_KVM_GUEST=true

export RESEARCH_UNPRIV_BPF RESEARCH_SCX_LOADER RESEARCH_BPFTOOL RESEARCH_COMMIT RESEARCH_TIER
RESEARCH_UNPRIV_BPF="$(cat /proc/sys/kernel/unprivileged_bpf_disabled 2>/dev/null || echo unknown)"
RESEARCH_SCX_LOADER=""
command -v scx_loader >/dev/null 2>&1 && RESEARCH_SCX_LOADER="$(command -v scx_loader)"
RESEARCH_BPFTOOL=""
command -v bpftool >/dev/null 2>&1 && RESEARCH_BPFTOOL="$(bpftool version 2>/dev/null | head -1 || true)"
RESEARCH_COMMIT="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
RESEARCH_TIER="R0"
[[ "${RESEARCH_HAS_SCHED_EXT}" == true ]] && RESEARCH_TIER="R1"

export RESEARCH_PREFLIGHT_OUT="${OUT}"
python3 <<'PY'
import json, os, datetime

def b(name):
    return os.environ.get(name, "false") == "true"

doc = {
    "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "hostname": os.environ["RESEARCH_PREFLIGHT_HOST"],
    "kernel_release": os.environ["RESEARCH_PREFLIGHT_KERNEL"],
    "research_tier": os.environ["RESEARCH_TIER"],
    "repo_commit": os.environ["RESEARCH_COMMIT"],
    "capabilities": {
        "has_sched_ext": b("RESEARCH_HAS_SCHED_EXT"),
        "has_btf": b("RESEARCH_HAS_BTF"),
        "has_bpf_syscall": b("RESEARCH_HAS_BPF_SYSCALL"),
        "has_kvm_guest": b("RESEARCH_HAS_KVM_GUEST"),
        "unprivileged_bpf_disabled": os.environ.get("RESEARCH_UNPRIV_BPF", "unknown"),
        "scx_loader": os.environ.get("RESEARCH_SCX_LOADER") or None,
        "bpftool": os.environ.get("RESEARCH_BPFTOOL") or None,
    },
    "charter": "research/BYPASS_CLAIM_CHARTER.md",
    "elite_offline_forbidden": True,
}
out = os.environ["RESEARCH_PREFLIGHT_OUT"]
with open(out, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
print(json.dumps(doc, indent=2))
PY

# shellcheck source=scripts/research/research-log.sh
source "$(dirname "${BASH_SOURCE[0]}")/research-log.sh"
research_log "live_preflight" "PASS" "${OUT}" "tier=${RESEARCH_TIER}"
echo "LIVE_PREFLIGHT_OK path=${OUT}"
