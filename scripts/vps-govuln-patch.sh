#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/go/bin:/usr/bin:/bin
export GOPATH=/src/.gopath
export GOCACHE=/src/.gocache
cd /src
go get golang.org/x/text@v0.41.0 \
  golang.org/x/net@v0.57.0 \
  go.opentelemetry.io/otel@v1.43.0 \
  go.opentelemetry.io/otel/sdk@v1.43.0 \
  go.opentelemetry.io/otel/sdk/metric@v1.43.0 \
  go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp@v1.43.0
go mod tidy
CGO_ENABLED=0 go build -o /tmp/elite-agent-bump ./cmd/exporter
echo PATCH_DONE
grep -E 'golang.org/x/(net|text) |otlpmetrichttp' go.mod
