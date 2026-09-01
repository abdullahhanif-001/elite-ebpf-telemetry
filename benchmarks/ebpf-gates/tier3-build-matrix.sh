#!/usr/bin/env bash
# tier3-build-matrix.sh — rebuild scheduler-matrix.json from tier3-simple verdicts.
set -euo pipefail
OUT="${FLOOD_OUT:-/opt/elite/src/scripts/oneclick/results/rt-guard-flood-safe-20260831-062351}"
JSON="${OUT}/scheduler-matrix.json"
ftrace=yes
[[ -f /proc/sys/kernel/ftrace_enabled ]] || ftrace=no
echo '{"mode":"tier3_ftrace","ftrace":"'"${ftrace}"'","schedulers":[' > "${JSON}"
first=1
for s in bpfland lavd rusty flash rustland layered; do
  v="FAIL"
  [[ -f "${OUT}/schedulers/${s}/verdict.txt" ]] && v="$(cat "${OUT}/schedulers/${s}/verdict.txt" | cut -d= -f2)"
  [[ "${first}" -eq 1 ]] || echo ',' >> "${JSON}"
  echo "{\"name\":\"${s}\",\"result\":\"${v}\",\"ftrace\":\"${ftrace}\"}" >> "${JSON}"
  first=0
done
echo ']}' >> "${JSON}"
cat "${JSON}"
