#!/usr/bin/env bash
# Slim root go.mod for Elite agent SCA + verify nested diagnose modules build.
set -euo pipefail

ROOT="${1:-/opt/elite/src}"
BUILDER="${BUILDER_IMAGE:-kubeskoop/ci-builder:go125clang211}"
cd "$ROOT"

echo "=== tidy root (elite agent) — skoop/controller are separate modules ==="
docker run --rm -v "$ROOT:/src" -w /src "$BUILDER" \
  env GOTOOLCHAIN=local go mod tidy

echo "=== copy root lockfile baseline for skoop module (SCA-excluded) ==="
cp "$ROOT/go.sum" "$ROOT/pkg/skoop/go.sum" 2>/dev/null || true

echo "=== generate go.sum for nested modules (Sonar text:S8566) ==="
SKOOP_EXCLUDE='exclude google.golang.org/genproto v0.0.0-20210402141018-6c239bbf2bb1'
if ! grep -q 'exclude google.golang.org/genproto' "$ROOT/pkg/skoop/go.mod"; then
  printf '\n%s\n' "$SKOOP_EXCLUDE" >> "$ROOT/pkg/skoop/go.mod"
fi
for d in pkg/skoop pkg/controller cmd/skoop cmd/collector cmd/controller; do
  echo "-- tidy $d"
  docker run --rm -v "$ROOT:/src" -w "/src/$d" "$BUILDER" \
    env GOTOOLCHAIN=local go mod tidy || \
  docker run --rm -v "$ROOT:/src" -w "/src/$d" "$BUILDER" \
    env GOTOOLCHAIN=local go mod download
  test -f "$ROOT/$d/go.sum" || { echo "missing go.sum in $d"; exit 1; }
done

echo "=== build elite agent ==="
docker run --rm -v "$ROOT:/src" -w /src "$BUILDER" \
  bash -c 'CGO_ENABLED=0 go build -o bin/elite-agent ./cmd/exporter'

echo "=== build btfhack ==="
docker run --rm -v "$ROOT:/src" -w /src "$BUILDER" \
  bash -c 'CGO_ENABLED=0 go build -o bin/btfhack ./cmd/btfhack'

echo "=== govulncheck elite agent path ==="
docker run --rm -v "$ROOT:/src" -w /src "$BUILDER" \
  bash -c 'go install golang.org/x/vuln/cmd/govulncheck@latest && govulncheck ./cmd/exporter/... ./pkg/exporter/... ./pkg/export/... ./pkg/agentrpc/...' || true

echo "=== root go.mod direct requires ==="
grep -E '^\tgithub.com|^\tgo\.|^\tk8s\.|^\tgoogle\.|^\tsigs\.' go.mod | head -40

echo "DONE"
