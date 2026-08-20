#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/go/bin:/usr/bin:/bin
export GOPATH=/src/.gopath
export GOCACHE=/src/.gocache
mkdir -p "$GOPATH" "$GOCACHE"
TAG=vps-test GIT_COMMIT=none make build-elite-agent
ls -lh bin/elite-agent
go install golang.org/x/vuln/cmd/govulncheck@latest
"$GOPATH/bin/govulncheck" ./cmd/exporter ./pkg/exporter/security ./pkg/export || true
echo BUILD_VULN_DONE
