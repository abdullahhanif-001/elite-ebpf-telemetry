#!/usr/bin/env bash
# global-ebpf-inventory.sh — scan all eBPF surfaces → our-goal/inventory.json
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ebpf-gates-common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/our-goal-log.sh"

ROOT="$(ebpf_repo_root)"
OUT="${OUR_GOAL_DIR}/inventory.json"
ebpf_ensure_our_goal

python3 - "${ROOT}" "${OUT}" <<'PY'
import json, os, sys, glob
from pathlib import Path

root = Path(sys.argv[1])
out = Path(sys.argv[2])

WIRED = {
    "connect_trace.c": "traceconnect",
    "flow.c": "flow",
    "kernellatency.c": "tracekernel",
    "netiftxlatency.c": "tracenetiftxlatency",
    "packetloss.c": "tracepacketloss",
    "socketlatency.c": "tracesocketlatency",
    "softirq.c": "tracesoftirq",
    "tcpretrans.c": "tracetcpretrans",
    "tcpreset.c": "tracetcpreset",
    "tracebiolatency.c": "tracebiolatency",
    "virtcmdlatency.c": "tracevirtcmdlat",
}
ORPHANS = {"tasklatency.c", "nflatancy.c", "flowcount.c", "netns.c", "rxkernel.c", "txkernel.c"}

def probe_has_test(loader):
    p = root / "pkg/exporter/probe" / loader
    if not p.is_dir():
        return False
    return any(p.glob("*_test.go"))

items = []
for c in sorted((root / "bpf").glob("*.c")):
    name = c.name
    loader = WIRED.get(name)
    holes = []
    if name in ORPHANS:
        holes.append("ORPHAN")
    elif not loader:
        holes.append("UNWIRED")
    has_test = probe_has_test(loader) if loader else False
    items.append({
        "path": str(c.relative_to(root)).replace("\\", "/"),
        "type": "elite_bpf",
        "loader": loader or None,
        "has_test": has_test,
        "holes": holes,
    })

for p in sorted((root / "contrib/sched-ext").rglob("*")):
    if p.suffix in (".c", ".h", ".patch") or p.name.endswith(".bpf.c"):
        items.append({
            "path": str(p.relative_to(root)).replace("\\", "/"),
            "type": "sched_ext_contrib",
            "loader": None,
            "has_test": "selftest" in str(p),
            "holes": [],
        })

for patch in (root / "contrib/sched-ext/kernel").glob("*.patch"):
    items.append({
        "path": str(patch.relative_to(root)).replace("\\", "/"),
        "type": "kernel_patch",
        "loader": None,
        "has_test": False,
        "holes": [],
    })

gates = list((root / "benchmarks/sched-ext-gates").glob("*.sh"))
gates += list((root / "benchmarks/server-gates").glob("*.sh"))
gates += list((root / "benchmarks/ebpf-gates").glob("*.sh"))
for g in sorted(set(gates)):
    items.append({
        "path": str(g.relative_to(root)).replace("\\", "/"),
        "type": "gate_script",
        "loader": None,
        "has_test": False,
        "holes": [],
    })

if (root / "bpf/xdp_mitigator.c").is_file():
    items.append({
        "path": "bpf/xdp_mitigator.c",
        "type": "xdp",
        "loader": "xdp-attach.sh",
        "has_test": (root / "scripts/oneclick/ebpf-xray-real-proof.sh").is_file(),
        "holes": [],
    })

summary = {
    "generated": __import__("datetime").datetime.utcnow().strftime("%Y-%m-%dT%H:%MZ"),
    "elite_bpf_count": len(list((root / "bpf").glob("*.c"))),
    "wired_count": len(WIRED),
    "orphan_count": len(ORPHANS),
    "items": items,
}
out.write_text(json.dumps(summary, indent=2))
print(f"INVENTORY_OK count={len(items)} out={out}")
PY

our_goal_log "D1_inventory" "PASS" "${OUT}" "elite+contrib+gates scanned"
