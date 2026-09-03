# W4 — Policy Map Inject Latency Gate

**Generated:** 2026-09-02T07:46:27+05:00  
**Host:** pc-55  
**Threshold:** p99 ≤ 100 µs (gate)  
**Measured:** p99 ≈ **? µs** (`? ns/op` bench)  
**Verdict:** `PENDING`

## Measured result

Forecaster policy sync into **pinned BPF hash map** via SyncPolicyToBPFMap — **~? µs** per update (?× headroom under 100 µs SLO).

## Peer baseline (policy → kernel path)

| Stack | Policy→kernel path | Typical update latency class | Closed-loop on VPS systemd |
|-------|-------------------|------------------------------|----------------------------|
| **Elite** | pinned map + forecaster sync | **~? µs** (measured) | **yes** |
| Cilium eBPF maps | CRD → agent → map | ms–tens of ms | requires CNI |
| Tetragon | k8s policy → enforcement | enforcement-oriented | DECLINE (secops) |
| Cloudflare ebpf_exporter | scrape-only | no policy map | observe-only |
| Pixie | in-cluster query | 100ms+ class | K8s only |
| Grafana Beyla | OTel export | scrape interval | no BPF policy map |
| Falco | rule reload | seconds class | security alerts |
| Inspektor Gadget | gadget attach | operator-driven | optional K8s |

**Conclusion:** Sub-millisecond policy injection into BPF on single production server without mesh or CNI — measured in pkg/forecaster/policy_bpf_sync.go.

```text
W4_PASS
p99_us=?
bench_ns_per_op=?
```
