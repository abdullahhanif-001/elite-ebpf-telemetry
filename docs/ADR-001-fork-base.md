# ADR-001: Fork KubeSkoop as Elite Base

## Status
Accepted

## Context
Istio sidecars and per-pod logging agents waste ~20% cluster CPU/RAM. Building from zero is slow and unproven.

## Decision
Fork [alibaba/kubeskoop](https://github.com/alibaba/kubeskoop) and customize:
- Rename metric namespace to `elite_`
- Slim probe set (physics layer only)
- Add `connecttrace` probe
- Add OTel OTLP export bridge
- One-click `elite-bundle.yaml`

## Consequences
- Userspace Go: Apache-2.0
- BPF programs in `/bpf`: GPL-2.0 (kernel compatibility)
- Upstream merges possible for probe improvements
