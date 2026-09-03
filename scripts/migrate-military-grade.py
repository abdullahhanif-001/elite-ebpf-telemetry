#!/usr/bin/env python3
"""One-shot repo migration: military-grade wording, server hostname, verdict tags."""
from __future__ import annotations

import os
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "node_modules", "vendor", ".cursor"}
SKIP_SUFFIXES = {".png", ".jpg", ".svg", ".ico", ".woff", ".woff2", ".plan.md"}

# Order matters — longer / more specific first.
REPLACEMENTS: list[tuple[str, str]] = [
    # Path segments (after dir rename, fix stale refs)
    ("benchmarks/server-gates/", "benchmarks/server-gates/"),
    ("deploy/server/", "deploy/server/"),
    ("scripts/server/", "scripts/server/"),
    ("/server/", "/server/"),
    # SSH host alias
    ("production-server", "production-server"),
    # Verdict tags
    ("SERVER_PHYSICS_VPS_PASS", "SERVER_PHYSICS_VPS_PASS"),
    ("SERVER_PHYSICS_VPS_PARTIAL", "SERVER_PHYSICS_VPS_PARTIAL"),
    ("SERVER_PHYSICS_VPS_UNVERIFIED", "SERVER_PHYSICS_VPS_UNVERIFIED"),
    ("SERVER_PHYSICS_VPS_PENDING", "SERVER_PHYSICS_VPS_PENDING"),
    ("ELITE_OPS_SCORE", "ELITE_OPS_SCORE"),
    ("ECGF_BENCH_PASS", "ECGF_BENCH_PASS"),
    ("ECGF_BENCH_INCONCLUSIVE", "ECGF_BENCH_INCONCLUSIVE"),
    ("SCX1202_MATRIX_PASS=YES", "SCX1202_MATRIX_PASS=YES"),
    ("SCX1202_MATRIX_PASS", "SCX1202_MATRIX_PASS"),
    ("LIMIT-SCX-", "LIMIT-SCX-"),
    # Doc cross-links (before generic renames)
    ("OPS_PROVIDER_SCORE.md", "OPS_PROVIDER_SCORE.md"),
    ("SERVER_CATEGORY_SCORECARD.md", "SERVER_CATEGORY_SCORECARD.md"),
    ("COMPETITOR_BASELINE_MATRIX.md", "COMPETITOR_BASELINE_MATRIX.md"),
    ("OPS_PROVIDER_SCORE.md", "OPS_PROVIDER_SCORE.md"),
    ("ops-proof-run.sh", "ops-proof-run.sh"),
    # Attribution
    ("Verification protocol — Abdullah Hanif. Start here.", "Verification protocol — Abdullah Hanif. Start here."),
    ("evidence is reproducible via public verifier — Abdullah Hanif, author", "evidence is reproducible via public verifier — Abdullah Hanif, author"),
    ("Documented limitations (LIMIT-SCX)", "Documented limitations (LIMIT-SCX)"),
    # Tone
    ("VPS Operational Evidence Pack", "VPS Operational Evidence Pack"),
    ("Operational read", "Operational read"),
    ("what operators audit", "what operators audit"),
    ("operators audit", "operators audit"),
    ("adversarial red-team", "adversarial red-team"),
    ("SCX1202 gate matrix H1–H12", "SCX1202 gate matrix H1–H12"),
    ("SCX1202 gate matrix H1-H12", "SCX1202 gate matrix H1-H12"),
    ("SCX1202 gate matrix #1202", "SCX1202 gate matrix #1202"),
    ("SCX1202 gate matrix sched_ext", "SCX1202 gate matrix sched_ext"),
    ("SCX1202 Gate Matrix", "SCX1202 Gate Matrix"),
    ("SCX1202 gate matrix", "SCX1202 gate matrix"),
    ("scx1202-matrix-verify", "scx1202-matrix-verify"),
    ("documented baseline comparison on production server", "documented baseline comparison on production server"),
    ("the measured stack that simultaneously", "the measured stack that simultaneously"),
    ("documented for Elite", "documented for Elite"),
    ("No competitor in COMPETITOR_BASELINE_MATRIX.md", "No peer in COMPETITOR_BASELINE_MATRIX.md"),
    ("COMPETITOR_BASELINE_MATRIX", "COMPETITOR_BASELINE_MATRIX"),
    ("Operational Provider Score", "Operational Provider Score"),
    ("Competitor baseline comparison", "Competitor baseline comparison"),
    ("Server Category", "Server Category"),
    ("server category", "server category"),
    ("Server category", "Server category"),
    # production servername (prose) — after path fixes
    ("production server", "production server"),
    ("production server", "production server"),
    ("on server", "on server"),
    ("Server ", "Server "),
    ("Server,", "Server,"),
    ("Server.", "Server."),
    ("server\n", "Server\n"),
    ("server", "server"),
    ("server", "server"),
    # Claim charter scoped phrases
    ("server_physics_vps", "server_physics_vps"),
    ("SERVER_PHYSICS_VPS", "SERVER_PHYSICS_VPS"),
    ("#1 Server physics-speed", "#1 server physics-speed"),
    ("Server physics-speed", "server physics-speed"),
]

RENAME_FILES = [
    ("docs/OPS_PROVIDER_SCORE.md", "docs/OPS_PROVIDER_SCORE.md"),
    ("docs/SERVER_CATEGORY_SCORECARD.md", "docs/SERVER_CATEGORY_SCORECARD.md"),
    ("docs/COMPETITOR_BASELINE_MATRIX.md", "docs/COMPETITOR_BASELINE_MATRIX.md"),
    ("scripts/oneclick/ops-proof-run.sh", "scripts/oneclick/ops-proof-run.sh"),
    ("scripts/oneclick/scx1202-matrix-verify.sh", "scripts/oneclick/scx1202-matrix-verify.sh"),
    ("benchmarks/ebpf-gates/scx1202-matrix-verify.sh", "benchmarks/ebpf-gates/scx1202-matrix-verify.sh"),
]


def should_process(path: Path) -> bool:
    if any(part in SKIP_DIRS for part in path.parts):
        return False
    if path.suffix in SKIP_SUFFIXES:
        return False
    if path.name.endswith(".plan.md"):
        return False
    return True


def migrate_text(content: str) -> str:
    for old, new in REPLACEMENTS:
        content = content.replace(old, new)
    # Table cells: WIN / PEER / DECLINE in comparison tables only (careful)
    content = re.sub(r"\|\s*\*\*WIN\*\*\s*\|", "| **PASS** |", content)
    content = re.sub(r"\|\s*WIN\s*\|", "| PASS |", content)
    content = re.sub(r"\|\s*PEER\s*\|", "| BASELINE |", content)
    content = re.sub(r"\|\s*DECLINE\s*\|", "| OUT_OF_SCOPE |", content)
    return content


def main() -> None:
    changed = 0
    for root, dirs, files in os.walk(REPO):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            path = Path(root) / name
            if not should_process(path):
                continue
            try:
                raw = path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            new = migrate_text(raw)
            if new != raw:
                path.write_text(new, encoding="utf-8", newline="\n")
                changed += 1
                print(f"updated: {path.relative_to(REPO)}")

    for old_rel, new_rel in RENAME_FILES:
        old = REPO / old_rel
        new = REPO / new_rel
        if old.is_file() and not new.exists():
            new.parent.mkdir(parents=True, exist_ok=True)
            old.rename(new)
            print(f"renamed: {old_rel} -> {new_rel}")

    print(f"DONE files_changed={changed}")


if __name__ == "__main__":
    main()
