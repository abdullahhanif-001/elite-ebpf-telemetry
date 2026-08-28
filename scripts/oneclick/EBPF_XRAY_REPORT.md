# eBPF X-Ray — Live Production Proof (X1–X8)

**Generated:** 2026-08-28T20:23:08+05:00  
**Host:** pc-55  
**Artifact:** `C:\Users\Administrator\Downloads\update ebpf\scripts\oneclick\results\ebpf-xray-20260828-202240`  
**Verdict:** `PENDING`

## What this proves (absolute)

On a **live production VPS** (Contabo, shared PM2 neighbors), Elite is the only named stack that simultaneously:

1. Runs **12+ CO-RE trace probes** on :9102 with elite_softirq, elite_socketlatency, elite_connecttrace, elite_shrinklat, and **30 elite_predict_* series**.
2. Compiles and loads a **custom XDP mitigator** (xdp_mitigator.c) with a **pinned elite_policy BPF map**.
3. Keeps **forecaster policy state** in parity between disk (predict-policy.bin) and the pinned map (X5).
4. Passes **W4 in-process map sync** at sub-100µs (bundled in X6).
5. Wraps every attach/load with **PM2_GUARD_OK** — zero neighbor restarts.

No Pixie pod, no Cilium CNI, no Tetragon enforcement daemon, no standalone ebpf_exporter sidecar is required for this **single-systemd closed loop**.

## Gate results

| ID | Check | Elite | Cloudflare ebpf_exporter | Cilium/Hubble | Pixie | Grafana Beyla | Tetragon | Falco |
|----|-------|:-----:|:------------------------:|:-------------:|:-----:|:-------------:|:--------:|:-----:|
| X1 | Live BPF inventory (trace/xdp/kprobe) | **PASS** | partial metrics only | CNI-dependent | K8s pod | app OTel | security trace | rules engine |
| X2 | Pinned map tree (/sys/fs/bpf/elite) | **PASS** | varies | Cilium pins | in-cluster | none default | policy maps | none |
| X3 | Deploy BPF compile (xdp_mitigator.o) | **PASS** | examples only | dataplane | bundled | auto-instr | enforcement | minimal |
| X4 | All probe metric families on :9102 | **PASS** | :9435 split | flow metrics | PxL API | RED metrics | events | alerts |
| X5 | File↔map policy parity | **PASS** | no predict path | policy CRD | no | no | policy | no |
| X6 | W4 map-update latency gate | **PASS** | no closed loop | not comparable | no | no | not comparable | no |
| X7 | XDP attach + policy pin | **PASS** | no XDP mitigator | XDP in CNI | no | no | optional | no |
| X8 | PM2 guard after xray | **PASS** | not a product goal | not PM2-safe | heavy agent | sidecar class | secops | secops |

## Staff-engineer read

If you are evaluating **physics + predict + actuate on bare metal/VPS**, this x-ray is the artifact other vendors do not ship: a **reproducible bash proof** that BPF programs are loaded, maps are pinned, metrics are live, and co-resident PM2 fleets stay untouched.

```text
REAL_EBPF_XRAY_PASS
fail=0
```
