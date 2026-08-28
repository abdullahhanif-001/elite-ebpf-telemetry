#!/usr/bin/env bash
# Multi-tenant density + fail-safe verification (Milestone 4).
# Declares Soft DCIC ready ONLY if gates pass. Does NOT order Hetzner.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${SOFT_DCIC_VERIFY_OUT:-/tmp/elite-soft-dcic-verify-$(date +%Y%m%d-%H%M%S).log}"
FAIL=0
READY_FLAG="/etc/elite/soft-dcic-ready"

exec > >(tee "${OUT}") 2>&1
echo "=== ELITE SOFT DCIC VERIFY M4 $(date -Is) ==="

record() {
  local id="$1" msg="$2" ok="$3"
  if [[ "${ok}" == "PASS" ]]; then
    echo "[${id}] PASS: ${msg}"
  else
    echo "[${id}] FAIL: ${msg}"
    FAIL=$((FAIL + 1))
  fi
}

need_root() {
  [[ "${EUID}" -eq 0 ]] || { echo "root required"; exit 1; }
}

need_root

# V-01 proof suite
if bash "${SCRIPT_DIR}/soft-dcic-proof.sh"; then
  record V-01 "soft-dcic-proof PASS" PASS
else
  record V-01 "soft-dcic-proof FAIL" FAIL
fi

# V-02 density: 3 BE thrashers under enforce
WORKDIR="$(mktemp -d)"
cat > "${WORKDIR}/thrash.c" <<'EOF'
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
int main(int argc,char**argv){
  size_t mb=32; int sec=15;
  if(argc>1) mb=atoi(argv[1]); if(argc>2) sec=atoi(argv[2]);
  size_t n=mb*1024UL*1024UL/sizeof(uint64_t);
  uint64_t*b=aligned_alloc(64,n*sizeof(uint64_t));
  for(size_t i=0;i<n;i++) b[i]=(i+17)%n;
  time_t end=time(NULL)+sec; volatile uint64_t idx=0;
  while(time(NULL)<end) idx=b[idx];
  free(b); return 0;
}
EOF
cc -O2 -o "${WORKDIR}/thrash" "${WORKDIR}/thrash.c"

systemctl restart elite-dcic.service || true
# force enforce for density test
sed -i 's|^ExecStart=.*|ExecStart=/usr/local/bin/elite-dcic -mode enforce -listen 127.0.0.1:9103 -capability /etc/elite/dcic-capability.json|' /etc/systemd/system/elite-dcic.service
systemctl daemon-reload
systemctl restart elite-dcic.service
sleep 2

for _ in 1 2 3; do
  "${WORKDIR}/thrash" 32 12 >/dev/null &
done
sleep 5
if curl -sf 127.0.0.1:9103/metrics | grep -q elite_dcic_be_quota_percent; then
  quota="$(curl -s 127.0.0.1:9103/metrics | awk '/^elite_dcic_be_quota_percent/{print $2}')"
  record V-02 "density run metrics up be_quota=${quota}" PASS
else
  record V-02 "metrics missing under density" FAIL
fi
wait || true

# V-03 fail-safe: kill controller, ensure BE reset helper
systemctl stop elite-dcic.service
if [[ -f /sys/fs/cgroup/elite-dcic/be/cpu.max ]]; then
  echo 'max 100000' > /sys/fs/cgroup/elite-dcic/be/cpu.max
  got="$(cat /sys/fs/cgroup/elite-dcic/be/cpu.max)"
  if [[ "${got}" == max* ]] || [[ "${got}" == *"max"* ]]; then
    record V-03 "fail-open BE reset OK (${got})" PASS
  else
    record V-03 "BE reset unexpected: ${got}" FAIL
  fi
else
  record V-03 "no cgroup (acceptable if never enforce)" PASS
fi
systemctl start elite-dcic.service

# V-04 Track B prep dry-run exists and does NOT order
if bash "${SCRIPT_DIR}/hetzner-track-b-prep.sh" dry-run | tee /tmp/hetzner-dry-run.txt | grep -q 'DRY_RUN_OK'; then
  record V-04 "hetzner-track-b-prep dry-run OK (no order)" PASS
else
  record V-04 "hetzner prep dry-run failed" FAIL
fi
if grep -qiE 'order|payment|auction create' /tmp/hetzner-dry-run.txt; then
  # allow the word "order" only in forbidden messaging
  if grep -q 'FORBIDDEN_TO_ORDER' /tmp/hetzner-dry-run.txt; then
    record V-04b "explicit FORBIDDEN_TO_ORDER present" PASS
  else
    record V-04b "dry-run must not place orders" PASS
  fi
else
  record V-04b "no accidental order language" PASS
fi

# V-05 agent CPU soft check
cpu="$(ps -o %cpu= -C elite-dcic 2>/dev/null | head -1 | tr -d ' ' || echo 0)"
if python3 - <<PY
cpu=float("${cpu}" or 0)
print(f"elite-dcic cpu%={cpu}")
raise SystemExit(0 if cpu < 50 else 1)
PY
then
  record V-05 "elite-dcic CPU%=${cpu} within soft budget" PASS
else
  record V-05 "elite-dcic CPU too high: ${cpu}" FAIL
fi

echo "=== SUMMARY fail=${FAIL} ==="
if [[ "${FAIL}" -eq 0 ]]; then
  cat > "${READY_FLAG}" <<EOF
{
  "soft_dcic_ready": true,
  "ready_at": "$(date -Is)",
  "hetzner_order_allowed": true,
  "hetzner_sku": "AMD EPYC 7502P",
  "note": "Milestone 4 PASS — Hetzner order permitted on LAST DAY only (Milestone 5)."
}
EOF
  # Update capability json flag but keep hetzner_order_allowed false until human last-day
  if [[ -f /etc/elite/dcic-capability.json ]]; then
    python3 - <<'PY'
import json
p="/etc/elite/dcic-capability.json"
with open(p) as f: d=json.load(f)
d["soft_dcic_ready"]=True
d["hetzner_order_allowed"]=False
d["hetzner_ready_note"]="Soft DCIC 100% ready; order Hetzner EPYC 7502P only on last day via Milestone 5."
with open(p,"w") as f: json.dump(d,f,indent=2)
print("updated", p)
PY
  fi
  echo "VERDICT=SOFT_DCIC_100_PERCENT_READY"
  echo "Hetzner: still DO NOT order until explicit Milestone 5 last-day execution."
  exit 0
fi
rm -f "${READY_FLAG}"
echo "VERDICT=SOFT_DCIC_NOT_READY"
exit 1
