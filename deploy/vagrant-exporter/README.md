# Vagrant test cluster — Elite eBPF exporter

Optional 3-node Kubernetes (1 master, 2 workers) with flannel and **Elite eBPF** agent for local testing.

## Setup

```shell
git clone https://github.com/abdullahhanif-001/elite-ebpf-telemetry.git
cd elite-ebpf-telemetry/deploy/vagrant-exporter
vagrant up
```

## Verify

Elite components install in the `elite` namespace:

```shell
kubectl get pod -n elite
```

When pods are ready, Grafana: [http://127.0.0.1:8080](http://127.0.0.1:8080) on the host.

**Note:** Legacy vagrant scripts may still reference old resource names; prefer `deploy/elite-bundle.yaml` for production-like installs.
