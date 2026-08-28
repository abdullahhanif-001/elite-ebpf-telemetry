#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/go/bin:/usr/bin:/bin
export GOPATH=/src/.gopath
export GOCACHE=/src/.gocache
mkdir -p "$GOPATH" "$GOCACHE"
cd /src

K8S=$(go list -m -versions k8s.io/client-go | tr ' ' '\n' | grep '^v0\.31\.' | tail -1)
echo "selected_k8s=$K8S"
go get k8s.io/api@"$K8S" \
  k8s.io/apimachinery@"$K8S" \
  k8s.io/client-go@"$K8S" \
  k8s.io/component-base@"$K8S" \
  k8s.io/cri-api@"$K8S" \
  k8s.io/klog/v2@v2.130.1 \
  sigs.k8s.io/controller-runtime@v0.19.7 \
  google.golang.org/grpc@v1.82.1

(cd webui && go get github.com/gin-gonic/gin@v1.10.1 golang.org/x/crypto@latest && go mod tidy)

go mod tidy

TAG=vps-test GIT_COMMIT=none CGO_ENABLED=0 go build -o /tmp/elite-agent-bump ./cmd/exporter
go test ./pkg/exporter/security/... ./pkg/export/... ./pkg/exporter/task-agent/... ./pkg/exporter/nettop/... -count=1
go install golang.org/x/vuln/cmd/govulncheck@latest
"$GOPATH/bin/govulncheck" ./cmd/exporter ./pkg/exporter/security ./pkg/export || true
echo K8S_BUMP_DONE
grep -E 'k8s.io/(api|apimachinery|client-go|cri-api) |controller-runtime|google.golang.org/grpc ' go.mod
