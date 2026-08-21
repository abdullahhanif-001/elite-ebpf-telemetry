# Kubernetes one-click path (Path B)

Do **not** reimplement Retina/KubeSkoop/Inspektor Gadget inside Elite. Apply upstream manifests.

## 1. KubeSkoop demo stack (Prometheus + Grafana + exporter)

```bash
kubectl apply -f https://raw.githubusercontent.com/alibaba/kubeskoop/main/deploy/skoopbundle.yaml
kubectl get svc -n kubeskoop webconsole
```

Default console user/password: see upstream README (`admin` / `kubeskoop`). Not for production.

## 2. Microsoft Retina (dropreason / packetforward metrics)

```bash
VERSION=$(curl -sL https://api.github.com/repos/microsoft/retina/releases/latest | jq -r .tag_name // .name)
helm upgrade --install retina oci://ghcr.io/microsoft/retina/charts/retina \
  --version "$VERSION" \
  --namespace kube-system \
  --set image.tag="$VERSION" \
  --set operator.tag="$VERSION" \
  --set logLevel=info \
  --set enabledPlugin_linux="[dropreason,packetforward,linuxutil,dns]"
```

Floor documented in `versions.env`: `RETINA_VERSION_FLOOR=v1.2.5`.

## 3. Inspektor Gadget

```bash
kubectl krew install gadget
kubectl gadget deploy --otel-metrics-listen=true
kubectl gadget run ghcr.io/inspektor-gadget/gadget/trace_tcpdrop:latest \
  --annotate=tcpdrop:metrics.collect=true \
  --otel-metrics-name=tcpdrop:tcpdrop-metrics \
  --detach
```

## 4. Elite DaemonSet (this repo)

```bash
kubectl apply -f deploy/elite-bundle.yaml
# or: ./install.sh --mode k8s
```

## 5. NetObserv flows (optional)

Use DaemonSet manifests from [netobserv/netobserv-ebpf-agent](https://github.com/netobserv/netobserv-ebpf-agent) — do not vendor their BPF into Elite.

## Scrape

Point cluster Prometheus at Elite `:9102`, Retina ServiceMonitors, and Gadget metrics port as documented upstream. VPS scrape snippet lives in `prometheus-scrape.yml` for bare metal only.
