#!/usr/bin/env bash
# emit-verification-manifest.sh — immutable evidence MANIFEST.json for a stamp dir.
# Usage: bash emit-verification-manifest.sh /opt/elite/evidence/VERIFICATION_<stamp>
set -euo pipefail

OUT_DIR="${1:-}"
[[ -n "${OUT_DIR}" ]] || { echo "usage: $0 <evidence-dir>" >&2; exit 1; }
mkdir -p "${OUT_DIR}"

SRC="${ELITE_SRC:-/opt/elite/src}"
AGENT_BIN="${ELITE_AGENT_BIN:-/opt/elite/bin/elite-agent}"

git_sha="unknown"
if [[ -d "${SRC}/.git" ]]; then
  git_sha="$(git -C "${SRC}" rev-parse HEAD 2>/dev/null || echo unknown)"
fi

agent_sha="missing"
if [[ -x "${AGENT_BIN}" ]]; then
  agent_sha="$(sha256sum "${AGENT_BIN}" | awk '{print $1}')"
fi

src_bin_sha="missing"
if [[ -x "${SRC}/bin/elite-agent" ]]; then
  src_bin_sha="$(sha256sum "${SRC}/bin/elite-agent" | awk '{print $1}')"
fi

mem_avail="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
loadavg="$(cat /proc/loadavg)"
host="$(hostname)"
kernel="$(uname -r)"
stamp="$(basename "${OUT_DIR}")"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Collect verdict snippets from common paths
verdicts_file="${OUT_DIR}/verdicts.txt"
: > "${verdicts_file}"
for f in \
  "${SRC}/scripts/oneclick/results/gates-checklist-latest.txt" \
  /tmp/elite-run-safe-*.log \
  "${OUT_DIR}"/*.verdict \
  "${OUT_DIR}"/*.txt
do
  [[ -e "$f" ]] || continue
  # shellcheck disable=SC2086
  for path in $f; do
    [[ -f "${path}" ]] || continue
    grep -E 'PASS|FAIL|DEFERRED|H11_|CATEGORY_|GATES_|ELITE_RUN_SAFE_|REAL_CLOSED' "${path}" 2>/dev/null \
      | head -n 40 >> "${verdicts_file}" || true
  done
done

python3 - <<PY
import json, os
manifest = {
  "stamp": "${stamp}",
  "ts_utc": "${ts}",
  "host": "${host}",
  "kernel": "${kernel}",
  "git_sha": "${git_sha}",
  "agent_sha256": "${agent_sha}",
  "src_agent_sha256": "${src_bin_sha}",
  "binary_match": ("${agent_sha}" == "${src_bin_sha}" and "${agent_sha}" != "missing"),
  "mem_available_kb": int("${mem_avail}" or "0"),
  "loadavg": "${loadavg}",
  "real_only": os.environ.get("REAL_ONLY", ""),
  "flood_safe_mode": os.environ.get("FLOOD_SAFE_MODE", ""),
  "xdp_iface": os.environ.get("ELITE_XDP_IFACE", ""),
  "taxonomy": {
    "PASS": "required verdict + exit 0",
    "FAIL": "blocks green",
    "DEFERRED": "out of scope; not scored green",
    "N/A": "precondition absent; not PASS",
  },
}
path = os.path.join("${OUT_DIR}", "MANIFEST.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
print("MANIFEST_OK", path)
print(json.dumps(manifest, indent=2))
PY
