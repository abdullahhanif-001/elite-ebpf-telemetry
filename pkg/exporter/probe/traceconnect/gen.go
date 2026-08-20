//go:build ignore

// Run: make generate-connect-bpf
//go:generate bpf2go -target=${GOARCH} -cc clang -cflags $BPF_CFLAGS -type insp_connect_event_t -type insp_connect_metric_t bpf ../../../../bpf/connect_trace.c -- -I../../../../bpf/headers -D__TARGET_ARCH_${GOARCH}

package traceconnect
