# Sidecar Removal Migration Guide

Replace Istio Envoy sidecars + per-pod logging agents with Elite (1 DaemonSet/node).

## Phase 1 — Deploy Elite (no sidecar changes yet)

```bash
kubectl apply -f deploy/elite-bundle.yaml
kubectl get pods -n elite -w
```

Verify metrics:

```bash
kubectl port-forward -n elite svc/prometheus 9090:9090
# Query: elite_socketlatency_read1ms
```

## Phase 2 — Validate parity

| Istio/Kiali metric | Elite equivalent |
|--------------------|------------------|
| Request latency | `elite_socketlatency_*` |
| TCP errors | `elite_packetloss_*` |
| Service graph | Grafana physics dashboard |

## Phase 3 — Disable sidecar injection

```bash
kubectl label namespace <your-ns> istio-injection- --overwrite
kubectl rollout restart deployment -n <your-ns>
```

## Phase 4 — Remove logging sidecars

Remove Fluent Bit/Filebeat from pod specs; Elite events flow to stderr/Loki via ConfigMap sinks.

## Phase 5 — Confirm savings

```bash
./benchmarks/run-overhead.sh
kubectl top nodes
```

Expected: ≥15% cluster CPU reduction at 100+ pods.

## mTLS still needed?

Elite is **observability-only**. For mTLS/traffic policy use Istio Ambient mode or Cilium Service Mesh alongside Elite.
