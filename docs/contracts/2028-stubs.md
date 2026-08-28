# 2028 metric contracts (stubs — no fake implementations)

Reserved series names for future hardware. Populate only when counters exist.

| Prefix | Intent |
|--------|--------|
| `elite_cxl_*` | CXL memory bandwidth / latency |
| `elite_dpu_*` | DPU/BlueField scrape contract |
| `elite_gpu_host_*` | Host softirq/LLC joined with NVML when present |
| `elite_sched_ext_*` | sched_ext presence / runqueue (observe only) |
| `elite_af_xdp_*` | AF_XDP readiness checklist |

See ADR-004. Do not claim these features until implementations land.
