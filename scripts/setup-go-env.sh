#!/usr/bin/env bash
#
# Points Go's module cache (GOMODCACHE) and build cache (GOCACHE) at .go/
# inside the repo checkout instead of the default ~/go and ~/.cache/go-build,
# which can grow to a few GB per machine. Handy on small disks or shared
# boxes. .go/ is already in .gitignore.
#
# This is a per-user `go env` setting, not repo-specific config — it applies
# to any Go project built on that machine afterward. Run it once per
# machine/user, not per clone.
#
# Usage:
#   ./scripts/setup-go-env.sh
#
# Run this from anywhere in the repo; the paths below are relative to the
# project root (where this script lives inside scripts/).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v go >/dev/null 2>&1; then
  echo "go not found. Install it before continuing."
  exit 1
fi

mkdir -p "$REPO_ROOT/.go/mod" "$REPO_ROOT/.go/build"
go env -w GOMODCACHE="$REPO_ROOT/.go/mod"
go env -w GOCACHE="$REPO_ROOT/.go/build"

echo "GOMODCACHE=$(go env GOMODCACHE)"
echo "GOCACHE=$(go env GOCACHE)"
