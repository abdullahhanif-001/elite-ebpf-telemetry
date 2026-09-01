# Elite eBPF Documentation

Personal open-source project by **Abdullah Hanif**.

## Engineering references

- [Test and benchmark registry](TEST_BENCHMARK_REGISTRY.md) — all gates, orchestrators, evidence index
- [eBPF feature inventory](EBPF_FEATURE_INVENTORY.md) — probes, control plane, exporters, deployment

## Architecture and product

- [Physics metrics](physics-metrics.md)
- [Sidecar removal](sidecar-removal.md)
- [Predictive forecaster (EWMA)](predictive-forecaster.md)
- [Global eBPF verification report](GLOBAL_EBPF_VERIFICATION_REPORT.md)
- [SCX#1202 evidence index](evidence/scx-1202/README.md)

## ADRs

- [ADR-001: Architecture base](ADR-001-fork-base.md)
- [ADR-003: One-click OSS compose (Physics Pack)](ADR-003-oneclick-oss-compose.md)
- [ADR-004: Closed-loop predict → actuate](ADR-004-closed-loop-predict-actuate.md)
- [ADR-005: Track C ECGF](ADR-005-track-c-ecgf.md)
- [ADR-006: Predictive XDP shedding](ADR-006-predictive-xdp-shedding.md)
- [ADR-007: XDP v3 admission](ADR-007-xdp-v3-admission.md)

## Operations

- [One-click Physics Pack (VPS)](../scripts/oneclick/README.md)
- [One-click orchestrator](../scripts/oneclick/elite-oneclick.sh) (`--profile closed-loop`)
- [Main README](../README.md)
