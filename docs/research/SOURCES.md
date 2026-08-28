# Research Sources — Elite Track C (ECGF)

**Claim tags:** FACT | EXISTING RESEARCH | HYPOTHESIS | PROPOSED DESIGN | UNPROVEN

## Tier 1 — Kernel / official

- Linux BPF docs / `bpf(2)` — FACT
- Landlock LSM documentation (kernel.org) — FACT
- seccomp / seccomp_unotify — FACT

## Tier 2 — Runtime security / mesh (official + engineering)

- [Tetragon](https://tetragon.io/) — in-kernel filter + SIGKILL/Override — EXISTING RESEARCH
- [Falco](https://falco.org/) — userspace detection — EXISTING RESEARCH
- [Cilium Mutual Authentication](https://docs.cilium.io/en/latest/network/servicemesh/mutual-authentication/mutual-authentication/) — beta mTLS sidecarless — EXISTING RESEARCH
- Cloudflare ebpf_exporter — EXISTING RESEARCH (Elite Physics Pack compose)

## Tier 3 — Papers / academic

- VEP: Two-stage Verification Toolchain (NSDI 2025) — EXISTING RESEARCH
- VeriFence: Spectre defenses for untrusted BPF — EXISTING RESEARCH
- “The eBPF Runtime in the Linux Kernel” (arXiv 2410.00026) — EXISTING RESEARCH
- AgentCgroup (arXiv 2602.09345) — AI agent cgroup/sched_ext — EXISTING RESEARCH

## Tier 4 — AI agent consequence sandboxes

- [Sandlock](https://github.com/multikernel/sandlock) — Landlock + seccomp — EXISTING RESEARCH
- [ActPlane](https://github.com/eunomia-bpf/actplane) — BPF-LSM agent policies — EXISTING RESEARCH
- [agent-lock](https://github.com/yeet-src/agent-lock) — BPF LSM path jail — EXISTING RESEARCH

## Tier 5 — Elite internal (not prior art)

- ADR-003 / ADR-004 — FACT (repo policy)
- WORLD_EBPF_COMPARISON / HEAVY scorecards — FACT (claims; honesty gaps noted in NOVEL_GAP)
