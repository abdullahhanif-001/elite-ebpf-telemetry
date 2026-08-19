//go:build elite_bpf

package traceconnect

// connecttrace_bpf.go: enhanced sys_enter_connect eBPF probe.
// Enable with: go build -tags elite_bpf
// Requires: make generate-connect-bpf (Linux + clang)

// See bpf/connect_trace.c and connecttrace.go for userspace fallback.
