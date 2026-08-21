# Elite Physics Pack — third-party attribution

This pack **composes** upstream projects. It does not claim authorship of their BPF programs.

| Component | Project | License (see upstream) | Role in pack |
| --- | --- | --- | --- |
| Elite agent | [abdullahhanif-001/elite-ebpf-telemetry](https://github.com/abdullahhanif-001/elite-ebpf-telemetry) (KubeSkoop lineage) | Apache-2.0 / GPL-2.0 BPF | Base `elite_*` physics on `:9102` |
| ebpf_exporter | [cloudflare/ebpf_exporter](https://github.com/cloudflare/ebpf_exporter) | MIT | Softirq / kfree_skb / shrinklat / TCP retransmit on `:9435` |
| netstacklat config (optional) | [xdp-project/bpf-examples](https://github.com/xdp-project/bpf-examples) | GPL-2.0+ | Vendored YAML only; build upstream if enabled |
| Inspektor Gadget | [inspektor-gadget/inspektor-gadget](https://github.com/inspektor-gadget/inspektor-gadget) | Apache-2.0 | Host `ig` + optional tcpdrop metrics `:2224` |
| BCC tools | [iovisor/bcc](https://github.com/iovisor/bcc) via `bpfcc-tools` | Apache-2.0 | `softirqs` / `tcpdrop` CLI helpers |
| Retina (K8s) | [microsoft/retina](https://github.com/microsoft/retina) | MIT | Helm dropreason plugins |
| KubeSkoop bundle (K8s) | [alibaba/kubeskoop](https://github.com/alibaba/kubeskoop) | Apache-2.0 | `skoopbundle.yaml` one-click |

Pinned versions: [`versions.env`](versions.env).

**Marketing claim:** Elite One-Click Physics Pack = packaged Contabo/VPS + K8s compose under Elite branding — **not** “world’s first XDP/AI/kernel invention”.
