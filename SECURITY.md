# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | Yes       |

## Reporting a Vulnerability

Email: security@elite-io.dev

Do not open public issues for security vulnerabilities.

## Agent Privileges

Elite requires `NET_ADMIN`, `SYS_ADMIN`, `SYS_PTRACE` for eBPF. Run as DaemonSet with minimal RBAC.

## License

- Userspace Go: Apache-2.0
- BPF `/bpf`: GPL-2.0
