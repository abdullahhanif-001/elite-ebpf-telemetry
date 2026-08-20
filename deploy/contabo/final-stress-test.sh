#!/usr/bin/env bash
# FINAL STRESS TEST — PM2-safe chaos engineering for Elite eBPF agent
# Logs all raw output to /opt/elite/FINAL_STRESS_TEST.log
set -euo pipefail

LOG="/opt/elite/FINAL_STRESS_TEST.log"
BASELINE_RESTARTS=$(jq '[.[].pm2_env.restart_time] | add' /opt/elite/baseline/pm2-before.json)
TARGET_RESTARTS=131

exec > >(tee -a "$LOG") 2>&1

log() { echo "[$(date -Is)] $*"; }

guard() {
  if ! bash /opt/elite/scripts/pm2-guard.sh; then
    log "ABORT: PM2 guard failed — rolling back elite-agent"
    systemctl stop elite-agent 2>/dev/null || true
    exit 1
  fi
  local now
  now=$(pm2 jlist | jq '[.[].pm2_env.restart_time] | add')
  if [[ "$now" != "$TARGET_RESTARTS" ]]; then
    log "ABORT: PM2 restarts changed $TARGET_RESTARTS -> $now"
    systemctl stop elite-agent 2>/dev/null || true
    exit 1
  fi
}

rollback_check() {
  guard
  log "PM2_RESTARTS=$TARGET_RESTARTS UNCHANGED"
}

log "========== FINAL STRESS TEST START =========="
log "BASELINE_RESTARTS=$BASELINE_RESTARTS TARGET=$TARGET_RESTARTS"

# --- Ensure BTF cache ---
if [[ ! -f /opt/elite/btf/vmlinux ]]; then
  cp /sys/kernel/btf/vmlinux /opt/elite/btf/vmlinux 2>/dev/null || \
    ln -sf /sys/kernel/btf/vmlinux /opt/elite/btf/vmlinux
fi

# --- Start elite-agent if needed ---
if ! systemctl is-active --quiet elite-agent; then
  log "Starting elite-agent..."
  systemctl start elite-agent
fi

log "Waiting for metrics endpoint..."
for i in $(seq 1 24); do
  if curl -sf http://127.0.0.1:9102/metrics >/dev/null 2>&1; then
    log "Metrics ready after ${i} attempts"
    break
  fi
  sleep 10
done

guard
log "--- PM2 baseline ---"
pm2 jlist | jq '[.[].name, .[].pm2_env.status, .[].pm2_env.restart_time]'

log "--- Pre-stress resource snapshot ---"
systemctl show elite-agent -p ActiveState,MemoryCurrent,MemoryMax,CPUUsageNSec,CPUQuota

# =============================================================================
# TEST 1: BPF Map Exhaustion — 50k parallel TCP connection attempts
# =============================================================================
log "========== TEST 1: TCP connection flood (50k attempts) =========="
MEM_BEFORE=$(systemctl show elite-agent -p MemoryCurrent --value)
CPU_BEFORE=$(systemctl show elite-agent -p CPUUsageNSec --value)

python3 <<'PY'
import socket, threading, time, sys
TARGET = ("127.0.0.1", 19999)  # closed port — no PM2 impact
ATTEMPTS = 50000
WORKERS = 200
done = {"ok": 0, "err": 0}
lock = threading.Lock()

def worker(n):
    local_ok = local_err = 0
    for _ in range(n):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(0.05)
        try:
            s.connect(TARGET)
            local_ok += 1
        except Exception:
            local_err += 1
        finally:
            try: s.close()
            except: pass
    with lock:
        done["ok"] += local_ok
        done["err"] += local_err

per = ATTEMPTS // WORKERS
t0 = time.time()
threads = [threading.Thread(target=worker, args=(per,)) for _ in range(WORKERS)]
for t in threads: t.start()
for t in threads: t.join()
dt = time.time() - t0
rate = ATTEMPTS / dt if dt > 0 else 0
print(f"TCP_FLOOD attempts={ATTEMPTS} ok={done['ok']} err={done['err']} duration_s={dt:.2f} rate={rate:.0f}/s")
PY

sleep 5
MEM_AFTER=$(systemctl show elite-agent -p MemoryCurrent --value)
CPU_AFTER=$(systemctl show elite-agent -p CPUUsageNSec --value)
log "MEM_BEFORE=$MEM_BEFORE MEM_AFTER=$MEM_AFTER"
log "CPU_NSEC_DELTA=$((CPU_AFTER - CPU_BEFORE))"
journalctl -u elite-agent --since "2 min ago" --no-pager | grep -iE 'drop|lost|full|map|error' | tail -20 || log "No drop/error lines in journal"
rollback_check

# =============================================================================
# TEST 2: Kernel bypass / raw TCP probes
# =============================================================================
log "========== TEST 2: Raw TCP flag manipulation =========="
if command -v hping3 >/dev/null 2>&1; then
  timeout 15 hping3 -S -p 19998 -c 500 -i u1000 127.0.0.1 2>&1 | tail -5 || true
  timeout 10 hping3 -S -F -p 19997 -c 200 127.0.0.1 2>&1 | tail -5 || true
  log "hping3 SYN and SYN-FIN probes sent"
else
  python3 <<'PY'
import socket, struct
# SYN to closed port
s = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_TCP)
s.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)
# raw sockets need root — fallback to connect flood with short timeout
for i in range(500):
    c = socket.socket()
    c.settimeout(0.01)
    try: c.connect(("127.0.0.1", 19996))
    except: pass
    c.close()
print("RAW_TCP_FALLBACK=500 connect attempts to 19996")
PY
fi
dmesg -T 2>/dev/null | tail -5 | grep -iE 'bug|panic|oops|bpf' || log "KERNEL_PANIC_CHECK=none"
rollback_check

# =============================================================================
# TEST 3: Metrics endpoint exhaustion
# =============================================================================
log "========== TEST 3: Concurrent /metrics scrape flood =========="
python3 <<'PY'
import concurrent.futures, urllib.request, time, statistics
URL = "http://127.0.0.1:9102/metrics"
N = 100
CONC = 50

def fetch(_):
    t0 = time.perf_counter_ns()
    try:
        with urllib.request.urlopen(URL, timeout=10) as r:
            r.read()
        return time.perf_counter_ns() - t0, True
    except Exception as e:
        return 0, False

t0 = time.time()
with concurrent.futures.ThreadPoolExecutor(max_workers=CONC) as ex:
    results = list(ex.map(fetch, range(N)))
ok = sum(1 for _, s in results if s)
lats = sorted(l for l, s in results if s)
print(f"METRICS_FLOOD requests={N} concurrent={CONC} ok={ok} fail={N-ok}")
if lats:
    print(f"METRICS_LAT p50_ns={lats[len(lats)//2]} p99_ns={lats[int(len(lats)*0.99)]} max_ns={lats[-1]}")
print(f"METRICS_FLOOD duration_s={time.time()-t0:.2f}")
PY

systemctl show elite-agent -p MemoryCurrent,CPUUsageNSec
rollback_check

# =============================================================================
# TEST 4: SIGTERM graceful shutdown + stale BPF map check
# =============================================================================
log "========== TEST 4: SIGTERM + BPF map cleanup =========="
BPF_BEFORE=$(ls /sys/fs/bpf 2>/dev/null | wc -l)
log "BPF_PINNED_BEFORE=$BPF_BEFORE"
systemctl stop elite-agent
sleep 5
BPF_AFTER_STOP=$(ls /sys/fs/bpf 2>/dev/null | wc -l)
log "BPF_PINNED_AFTER_STOP=$BPF_AFTER_STOP"
ls -la /sys/fs/bpf 2>/dev/null || log "BPF dir empty or inaccessible"
journalctl -u elite-agent -n 15 --no-pager | tail -10

systemctl start elite-agent
for i in $(seq 1 18); do
  curl -sf http://127.0.0.1:9102/metrics >/dev/null 2>&1 && break
  sleep 10
done
BPF_AFTER_START=$(ls /sys/fs/bpf 2>/dev/null | wc -l)
log "BPF_PINNED_AFTER_RESTART=$BPF_AFTER_START"
rollback_check

# =============================================================================
# TEST 5: Corrupt config reload (fail-soft)
# =============================================================================
log "========== TEST 5: Corrupt config reload =========="
CFG=/opt/elite/config/config.yaml
BACKUP=/opt/elite/config/config.yaml.stress-bak
cp "$CFG" "$BACKUP"
echo "CORRUPT_YAML: [[[ invalid" >> "$CFG"
sleep 3
curl -sf -o /dev/null -w "METRICS_AFTER_CORRUPT=%{http_code}\n" http://127.0.0.1:9102/metrics || echo "METRICS_AFTER_CORRUPT=000"
mv "$BACKUP" "$CFG"
sleep 2
curl -sf -o /dev/null -w "METRICS_AFTER_RESTORE=%{http_code}\n" http://127.0.0.1:9102/metrics || echo "METRICS_AFTER_RESTORE=000"
rollback_check

# =============================================================================
# TEST 6: CPU/Memory average under sustained load
# =============================================================================
log "========== TEST 6: 60s sustained overhead sample =========="
(
  for _ in $(seq 1 30); do
    curl -sf http://127.0.0.1:9102/metrics >/dev/null &
  done
  wait
) &
LOAD_PID=$!

CPU_START=$(systemctl show elite-agent -p CPUUsageNSec --value)
MEM_PEAK=0
for i in $(seq 1 12); do
  m=$(systemctl show elite-agent -p MemoryCurrent --value)
  [ "$m" != "[not set]" ] && [ "$m" -gt "$MEM_PEAK" ] 2>/dev/null && MEM_PEAK=$m || true
  sleep 5
done
wait $LOAD_PID 2>/dev/null || true
CPU_END=$(systemctl show elite-agent -p CPUUsageNSec --value)
DELTA=$((CPU_END - CPU_START))
AVG_CORES=$(python3 -c "print(f'{($DELTA/1e9)/60:.6f}')")
MEM_MB=$(python3 -c "print(f'{$MEM_PEAK/1048576:.1f}')")
log "SUSTAINED_60s cpu_cores_avg=$AVG_CORES mem_peak_mb=$MEM_MB cpu_nsec_delta=$DELTA"
rollback_check

# =============================================================================
# TEST 7: BPF verifier proof (bpftool if available)
# =============================================================================
log "========== TEST 7: BPF verifier / probe status =========="
if command -v bpftool >/dev/null 2>&1; then
  bpftool prog list 2>/dev/null | grep -iE 'socket|softirq|packet|tcp' | head -20 || log "bpftool prog list empty"
  bpftool map list 2>/dev/null | head -15 || true
else
  log "bpftool not installed — using journal probe attach logs"
  journalctl -u elite-agent --no-pager | grep -E 'start metrics probe|failed start probe' | tail -10
fi

log "--- Final PM2 state ---"
pm2 jlist | jq '[.[].name, .[].pm2_env.status, .[].pm2_env.restart_time]'
guard
FINAL=$(pm2 jlist | jq '[.[].pm2_env.restart_time] | add')
log "FINAL_RESTARTS=$FINAL (expected $TARGET_RESTARTS)"
log "========== FINAL STRESS TEST COMPLETE =========="
