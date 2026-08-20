# Elite eBPF — Deploy

Personal brand by **Abdullah Hanif**. See [README.md](../README.md) for the full guide.

## Quick install (recommended)

```bash
git clone https://github.com/abdullahanifpro111-spec/elite-ebpf.git
cd elite-ebpf
chmod +x install.sh
./install.sh
```

Kubernetes bundle:

```bash
kubectl apply -f deploy/elite-bundle.yaml
kubectl get pod -n elite -l app=elite-agent -o wide
curl http://127.0.0.1:9102/metrics | grep elite_
```

## Helm

See [deploy/helm/README.md](helm/README.md). Default images: `ghcr.io/abdullahanifpro111-spec/elite-ebpf/agent`.

## Kubernetes

`kubectl apply -f deploy/elite-bundle.yaml`

## Bare metal (systemd)

See [deploy/contabo/](contabo/) for VPS/systemd install and audit scripts.
