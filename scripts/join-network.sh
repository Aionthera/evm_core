#!/usr/bin/env bash
#
# Prepares this computer to join as a full node on an Aionthera chain that
# ALREADY EXISTS and is already running in production (does not generate a
# new genesis — use scripts/init-chain.sh only for the original creation of
# the chain, once).
#
# After this script: run scripts/start-chain.sh, wait for it to sync
# (catching_up: false) and only then scripts/request-validator.sh.
#
# Usage:
#   ./scripts/join-network.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Variables — edit here
# ---------------------------------------------------------------------------

CHAIN_ID="${CHAIN_ID:-aionthera_78912-1}"
MONIKER="${MONIKER:-my-new-node}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_binary() {
  case "$(uname -s)" in
    Linux)
      case "$(uname -m)" in
        x86_64) echo "$REPO_ROOT/evm/build/aiontherad-linux-amd64" ;;
        aarch64|arm64) echo "$REPO_ROOT/evm/build/aiontherad-linux-arm64" ;;
      esac
      ;;
    MINGW*|MSYS*|CYGWIN*)
      case "$(uname -m)" in
        x86_64) echo "$REPO_ROOT/evm/build/aiontherad-windows-amd64.exe" ;;
        aarch64|arm64) echo "$REPO_ROOT/evm/build/aiontherad-windows-arm64.exe" ;;
      esac
      ;;
  esac
}
BINARY="${BINARY:-$(default_binary)}"
HOME_DIR="${HOME_DIR:-$HOME/.aiontherad}"

# Where to get the existing chain's genesis.json from. Can be:
#   - a local path (e.g. if you copied it via scp from another node beforehand)
#   - an http(s) URL (e.g. a /genesis.json endpoint you host)
# Defaults to the genesis.json published in the repo (network/genesis.json),
# same URL as GENESIS_JSON_URL in the front-end's chain.ts.
GENESIS_SOURCE="${GENESIS_SOURCE:-https://raw.githubusercontent.com/Aionthera/evm/refs/heads/main/network/genesis.json}"

# Peers of the existing network, in "node_id@ip:26656" format, comma-separated
# if more than one. Asked interactively below (defaults to this project's own
# seed node). Get a node_id by running this on a node that already works:
# `aiontherad comet show-node-id --home ~/.aiontherad`
PERSISTENT_PEERS="${PERSISTENT_PEERS:-}"
DEFAULT_SEED_NODE_ID="bd7db80c11284c07129e80d2e938fc3938303748"
DEFAULT_SEED_HOST="seed1.aionthera.org:26656"

# ---------------------------------------------------------------------------
# Initial checks
# ---------------------------------------------------------------------------

if [[ -z "$BINARY" || ! -x "$BINARY" ]]; then
  echo "No compiled binary found for this OS/arch (looked for: ${BINARY:-<none detected>})."
  echo "Available binaries in $REPO_ROOT/evm/build:"
  ls "$REPO_ROOT/evm/build" 2>/dev/null | sed 's/^/  /'
  echo "Build the release binaries with:"
  echo "  ./scripts/build-release.sh"
  echo "or set BINARY explicitly to override, e.g.:"
  echo "  BINARY=$REPO_ROOT/evm/build/aiontherad-linux-amd64 $0"
  exit 1
fi

if [[ -z "$GENESIS_SOURCE" ]]; then
  echo "GENESIS_SOURCE is not set."
  echo "Fill it in with the path/URL of the existing chain's genesis.json, e.g.:"
  echo "  GENESIS_SOURCE=https://myserver/genesis.json ./scripts/join-network.sh"
  echo "  GENESIS_SOURCE=/tmp/genesis.json ./scripts/join-network.sh"
  exit 1
fi

if [[ -z "$PERSISTENT_PEERS" ]]; then
  echo "Need the seed/peer's node_id? Run this ON THAT NODE (not this machine):"
  echo "  \$BINARY --home ~/.aiontherad comet show-node-id"
  echo "Leave blank to accept the defaults below (this project's public seed)."
  echo
  read -r -p "Seed node_id [$DEFAULT_SEED_NODE_ID]: " SEED_NODE_ID
  SEED_NODE_ID="${SEED_NODE_ID:-$DEFAULT_SEED_NODE_ID}"
  read -r -p "Seed host:port [$DEFAULT_SEED_HOST]: " SEED_HOST
  SEED_HOST="${SEED_HOST:-$DEFAULT_SEED_HOST}"
  PERSISTENT_PEERS="$SEED_NODE_ID@$SEED_HOST"
fi

if [[ -d "$HOME_DIR" ]]; then
  echo "Home already exists at: $HOME_DIR"
  read -r -p "Delete and recreate? [y/N] " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 1
  fi
  rm -rf "$HOME_DIR"
fi

# ---------------------------------------------------------------------------
# Local init (generates priv_validator_key.json, node_key.json, default
# configs — does NOT generate accounts or a gentx, this is not chain creation)
# ---------------------------------------------------------------------------

echo ">> init"
"$BINARY" --home "$HOME_DIR" init "$MONIKER" --chain-id "$CHAIN_ID"

# ---------------------------------------------------------------------------
# Real genesis from the existing network (replaces init's sample genesis)
# ---------------------------------------------------------------------------

echo ">> fetching the real genesis.json"
GENESIS_FILE="$HOME_DIR/config/genesis.json"

if [[ "$GENESIS_SOURCE" =~ ^https?:// ]]; then
  curl -fsSL "$GENESIS_SOURCE" -o "$GENESIS_FILE"
else
  cp "$GENESIS_SOURCE" "$GENESIS_FILE"
fi

FETCHED_CHAIN_ID="$(jq -r '.chain_id' "$GENESIS_FILE")"
if [[ "$FETCHED_CHAIN_ID" != "$CHAIN_ID" ]]; then
  echo "ERROR: the downloaded genesis's chain_id ($FETCHED_CHAIN_ID) doesn't match CHAIN_ID ($CHAIN_ID)."
  echo "Check GENESIS_SOURCE before continuing — don't force this."
  exit 1
fi

# ---------------------------------------------------------------------------
# Peers
# ---------------------------------------------------------------------------

echo ">> config.toml: persistent_peers"
sed -i "s/^persistent_peers = .*/persistent_peers = \"$PERSISTENT_PEERS\"/" "$HOME_DIR/config/config.toml"

# ---------------------------------------------------------------------------
# Same mandatory adjustments as init-chain.sh (init generates the default again)
# ---------------------------------------------------------------------------

echo ">> config.toml: mempool.type = app"
sed -i 's/^type = "flood"$/type = "app"/' "$HOME_DIR/config/config.toml"

echo ">> app.toml: [json-rpc] enable = true"
sed -i '/\[json-rpc\]/,/^\[/ s/^enable = false/enable = true/' "$HOME_DIR/config/app.toml"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo
echo "======================================================================"
echo "Node prepared at $HOME_DIR, NOT started yet."
echo "======================================================================"
echo
echo "Next steps:"
echo "  1) ./scripts/start-chain.sh"
echo "     (picks up the same HOME_DIR/CHAIN_ID defaults as this script —"
echo "     only pass them again if you overrode them above)"
echo "  2) Wait for it to sync (catching_up: false):"
echo "     curl -s http://127.0.0.1:26657/status | jq '.result.sync_info'"
echo "  3) Have an account with an aaion balance on this node — either import the"
echo "     same account from another node (keys add --recover, with its mnemonic),"
echo "     or create a new one and ask someone to send you aaion via tx bank send."
echo "  4) HOME_DIR=$HOME_DIR CHAIN_ID=$CHAIN_ID FROM_KEY=<account> ./scripts/request-validator.sh"
echo
echo "If this node is a SENTRY (the one exposing RPC/P2P to the internet, sitting"
echo "in front of a validator), the default P2P settings will drop the connection"
echo "to the validator repeatedly and stall tx propagation. Before going further,"
echo "follow the \"P2P configuration — sentry + validator\" section in"
echo "scripts/README.md to accept local/private IPs (addr_book_strict, pex,"
echo "persistent_peers, unconditional_peer_ids) on both this node and the validator."
echo "======================================================================"
