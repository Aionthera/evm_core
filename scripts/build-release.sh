#!/usr/bin/env bash
#
# Compila os binários de release para todas as plataformas:
#   linux/amd64, linux/arm64, windows/amd64, windows/arm64
#
# Usage:
#   ./scripts/build-release.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVM_DIR="$REPO_ROOT/evm"
BUILDDIR="$EVM_DIR/build"

log() { echo ">> $*"; }

# ---------------------------------------------------------------------------
# Go env
# ---------------------------------------------------------------------------

if ! command -v go >/dev/null 2>&1; then
  log "go not found — running setup-go-env.sh"
  "$REPO_ROOT/scripts/setup-go-env.sh"
fi

log "Go: $(go version)"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

log "Building all release targets (linux/windows × amd64/arm64)..."
make -C "$EVM_DIR" build-release

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
echo "======================================================================"
echo "Binaries written to: $BUILDDIR"
ls -lh "$BUILDDIR"/aiontherad-* 2>/dev/null || ls -lh "$BUILDDIR"
echo "======================================================================"
