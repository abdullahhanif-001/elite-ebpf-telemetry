# Elite eBPF

[English](./README.md) | 简体中文

**零侵入内核遥测 — 每节点一个 agent，CPU 低于 1%。**

**作者 / 创建者：** Abdullah Hanif  
**品牌：** Elite eBPF — 个人开源项目  
**仓库：** [github.com/abdullahhanif-001/elite-ebpf-telemetry](https://github.com/abdullahhanif-001/elite-ebpf-telemetry)

## 一键安装

```bash
git clone https://github.com/abdullahhanif-001/elite-ebpf-telemetry.git
cd elite-ebpf-telemetry
chmod +x install.sh
./install.sh
```

## 架构

```text
内核 tracepoint → eBPF CO-RE → elite-agent (Go) → Prometheus (:9102) + OTLP
```

完整文档见 [README.md](./README.md)。
