# Contributing to Elite eBPF

Elite eBPF is a personal open-source project by **Abdullah Hanif** — sole author and maintainer.

See [AUTHORS.md](../AUTHORS.md). Do not add third-party or AI agent names to commits or contributor lists.

## Development

```bash
make generate-bpf-in-container
make build-elite-agent
go test ./pkg/export/... ./pkg/exporter/probe/traceconnect/...
```

## Commits

Author: `Abdullah Hanif <abdullahhanif-001@users.noreply.github.com>`

Enable repo hooks (blocks automated co-author trailers):

```bash
git config core.hooksPath scripts/hooks
```

Run `bash scripts/audit-commit.sh` before commit — rejects AI/agent watermarks in messages.

## License

Userspace Apache-2.0; BPF `/bpf` GPL-2.0.
