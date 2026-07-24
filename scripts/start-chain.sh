#!/usr/bin/env bash
#
# Starts the already-initialized Aionthera node (run scripts/init-chain.sh
# first, if you haven't already).
#
# Usage:
#   ./scripts/start-chain.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Variables — edit here
# ---------------------------------------------------------------------------

CHAIN_ID="${CHAIN_ID:-aionthera_78912-1}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${BINARY:-$REPO_ROOT/evm/build/aiontherad}"
HOME_DIR="${HOME_DIR:-$HOME/.aiontherad}"

# debug | info | error
LOG_LEVEL="${LOG_LEVEL:-info}"

# Extra flags passed straight to `start` (e.g. "--pruning=nothing --trace")
EXTRA_FLAGS="${EXTRA_FLAGS:-}"

# ---------------------------------------------------------------------------
# Initial checks
# ---------------------------------------------------------------------------

if [[ ! -x "$BINARY" ]]; then
  echo ">> Binary not found at $BINARY — building it (make -C $REPO_ROOT/evm build)"
  "$REPO_ROOT/scripts/setup-go-env.sh"
  make -C "$REPO_ROOT/evm" build
  if [[ ! -x "$BINARY" ]]; then
    echo "Build finished but binary still not found at: $BINARY"
    exit 1
  fi
fi

if [[ ! -f "$HOME_DIR/config/genesis.json" ]]; then
  echo "Couldn't find genesis at $HOME_DIR/config/genesis.json"
  echo "Run scripts/init-chain.sh first (or adjust HOME_DIR)."
  exit 1
fi

# If data/ was manually deleted (e.g. rm -rf .../data to reset state),
# priv_validator_state.json needs to exist before starting.
STATE_FILE="$HOME_DIR/data/priv_validator_state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  echo ">> recreating $STATE_FILE"
  mkdir -p "$HOME_DIR/data"
  cat > "$STATE_FILE" <<'EOF'
{"height": "0", "round": 0, "step": 0}
EOF
fi

echo ">> Config: chain-id=$CHAIN_ID home=$HOME_DIR log-level=$LOG_LEVEL"
echo ">> Endpoints: 26657 (Tendermint RPC) · 1317 (REST) · 9090 (gRPC) · 8545/8546 (JSON-RPC EVM)"
echo

exec "$BINARY" --home "$HOME_DIR" start \
  --chain-id "$CHAIN_ID" \
  --log_level "$LOG_LEVEL" \
  $EXTRA_FLAGS
