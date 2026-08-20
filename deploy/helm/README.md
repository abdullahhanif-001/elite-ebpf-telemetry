# Elite eBPF Helm chart

Personal brand by **abdullah i**.

## Install from this repo

```shell
git clone https://github.com/abdullahanifpro111-spec/elite-ebpf.git
cd elite-ebpf

helm install -n elite --create-namespace elite-exporter ./deploy/helm --debug
```

Verify:

```shell
kubectl get pod -n elite -l app=elite-agent -o wide
curl http://<pod-ip>:9102/metrics | grep elite_
```

## Key values (`values.yaml`)

| Setting | Description | Default |
|---------|-------------|---------|
| `agent.image.repository` | Agent image | `ghcr.io/abdullahanifpro111-spec/elite-ebpf/agent` |
| `agent.image.tag` | Agent tag | `v1.0.0` |
| `agent.config.port` | Metrics HTTP port | `9102` |
| `config.metricProbes` | Enabled metric probes | see `values.yaml` |

Override namespace and credentials at install time — never commit production secrets.

```shell
helm upgrade --install elite-exporter ./deploy/helm \
  -n elite --create-namespace \
  --set webconsole.auth.username="$ELITE_WEB_USER" \
  --set webconsole.auth.password="$ELITE_WEB_PASS"
```
