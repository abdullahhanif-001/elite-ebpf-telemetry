# Contributing to Elite

Elite is a fork/customization of [KubeSkoop](https://github.com/alibaba/kubeskoop).

## Development

```bash
make generate-bpf-in-container  # requires Docker
make build-exporter
```

## Pull Requests

1. Fork the repo
2. Create feature branch
3. Run `go test ./...` on Linux
4. Ensure benchmarks pass SLO gates

## Code of Conduct

Be respectful. Follow CNCF community guidelines.
