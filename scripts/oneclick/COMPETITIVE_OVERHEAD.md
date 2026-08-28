# Competitive Overhead

**Generated:** 2026-08-24T09:27:25+02:00  
**Host:** production VPS (hostname redacted)

## Elite (measured or audited)

| Metric | Value | Source |
|--------|-------|--------|
| Agent CPU | cpu_cores_avg=0.000222 | Contabo speed proof / [AUDIT_SCORECARD.md](../../AUDIT_SCORECARD.md) |
| RSS / ceiling | rss_mb=72.2; systemd `MemoryMax=160M` | [deploy/contabo/elite-agent.service](../../deploy/contabo/elite-agent.service) |
| Host class | systemd VPS, no CNI required | Physics Pack |
| PM2 co-resident | PASS | pm2-guard |

## Competitors (cited public — not Contabo installs)

| Project | Footprint class (public) | Citation |
|---------|--------------------------|----------|
| Istio sidecar | ~500mCPU per pod (mesh tax) | Elite README comparison baseline; Istio proxy resource guidance |
| Pixie | Multi-GB / heavy in-cluster agent class | [Pixie docs — architecture / requirements](https://docs.px.dev/) |
| Microsoft Retina | K8s DaemonSet with plugin CPU/memory requests | [Retina docs](https://retina.net/) / Azure Container Networking |
| DeepFlow | Full APM/tracing stack (heavier than physics-only) | [DeepFlow docs](https://deepflow.io/docs/) |
| Tetragon | Security enforcement agent (different axis) | [Tetragon docs](https://tetragon.io/) — DECLINE SecOps |

## Verdict

Elite wins **memory + CPU + bare-metal VPS** versus Pixie/Istio sidecar tax; peers Retina on K8s drops only when both run in-cluster; declines Tetragon/DeepFlow product axes.

```text
ELITE_COMPETITIVE_OVERHEAD
pm2=PASS
VERDICT=OVERHEAD_WIN_VPS
```
