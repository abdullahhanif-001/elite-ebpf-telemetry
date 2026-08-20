FROM docker.io/library/golang:1.25.12-alpine3.24
ARG GOPROXY
RUN apk add clang21=21.1.8-r3 llvm21=21.1.8-r1 linux-headers git make bash && \
    ln -s /usr/bin/clang-21 /usr/local/bin/clang && \
    ln -s /usr/bin/llvm21-strip /usr/local/bin/llvm-strip
COPY tools/bpf2go/go.mod tools/bpf2go/go.sum /tmp/bpf2go/
WORKDIR /tmp/bpf2go
RUN if [[ -n "${GOPROXY}" ]]; then go env -w GOPROXY="${GOPROXY}"; fi && \
    go install -mod=readonly github.com/cilium/ebpf/cmd/bpf2go
RUN adduser -D -u 65532 elite
USER elite
