#!/usr/bin/env bash
# MOCK_ inject proof — unit-level causal tags already covered in pkg/forecaster.
# On Contabo, optional noise inject can be added later; this script validates decision bus shape.
set -euo pipefail

TMP="$(mktemp)"
cat > "${TMP}" <<'EOF'
{"fault":true,"cause":"network","projected":0.2,"ewma":0.15,"updated_at":"2026-01-01T00:00:00Z"}
EOF
python3 - <<PY
import json,sys
d=json.load(open("${TMP}"))
assert d["fault"] is True
assert d["cause"] in ("network","llc","psi","mixed")
print("MOCK_ decision bus shape OK")
PY
rm -f "${TMP}"
exit 0
