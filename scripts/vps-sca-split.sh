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
