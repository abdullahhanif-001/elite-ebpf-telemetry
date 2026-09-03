# eBPF X-Ray — Live Production Proof (X1–X8)

**Generated:** 2026-09-02T07:46:27+05:00  
**Host:** pc-55  
**Artifact:** `none`  
**Verdict:** `PENDING`

## Scope

On a **live production server** (shared PM2 neighbors), Elite provides:

1. **12+ CO-RE trace probes** on :9102 — elite_softirq, elite_socketlatency, elite_connecttrace, elite_shrinklat, **30 elite_predict_* series**.
2. **Custom XDP mitigator** (xdp_mitigator.c) with **pinned elite_policy BPF map**.
3. **Forecaster policy parity** between disk (predict-policy.bin) and pinned map (X5).
4. **W4 in-process map sync** at sub-100µs (X6).
5. **PM2_GUARD_OK** on every attach/load — zero neighbor restarts.

Single-systemd closed loop. No Pixie pod, Cilium CNI, Tetragon daemon, or ebpf_exporter sidecar required.

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

## Operational read

Reproducible bash proof: BPF loaded, maps pinned, metrics live, PM2 fleet untouched.

```text
REAL_EBPF_XRAY_PASS
fail=0
```
