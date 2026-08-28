# compose-obi

Optional OpenTelemetry eBPF Instrumentation (heavy). Off Contabo default.

Pin and run upstream OBI/Beyla separately; scrape OTLP/Prometheus into localhost Prometheus.
Keep `network.enabled: false` if Cilium eBPF dataplane is present.
