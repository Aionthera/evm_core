#!/usr/bin/env bash
#
# Edits an already-registered validator's parameters (commission rate,
# moniker, identity, website, security contact, details) on a live
# Aionthera chain via `tx staking edit-validator`.
#
# Prerequisites:
#   - The validator already exists on-chain (created via request-validator.sh).
#   - The operator account is in this node's keyring with enough balance for fees.
#
# Note: the chain enforces a minimum interval (default 24h) between
# commission-rate changes, and the new rate can't exceed the validator's
# commission-max-rate set at creation time.
#
# Usage:
#   COMMISSION_RATE=0.08 ./scripts/edit-validator.sh
#
# Override any variable with an env-var prefix:
#   FROM_KEY=validator COMMISSION_RATE=0.08 ./scripts/edit-validator.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Variables — edit here
# ---------------------------------------------------------------------------

CHAIN_ID="${CHAIN_ID:-aionthera_78912-1}"

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

# RPC endpoint of the chain where the tx will be broadcast. If your local
# node is the one that's already synced, leave the default.
NODE_RPC="${NODE_RPC:-tcp://localhost:26657}"

# Account that owns the validator being edited.
KEYRING_BACKEND="${KEYRING_BACKEND:-file}"
FROM_KEY="${FROM_KEY:-validator}"

# New commission rate (leave empty to skip changing it). Must be <= the
# commission-max-rate set at validator creation, and can only be changed
# once per commission-max-change-rate window (default 24h).
COMMISSION_RATE="${COMMISSION_RATE:-}"

# Other editable fields — leave empty to leave unchanged ("[do-not-modify]" is
# passed to the CLI when empty, which is its convention for "skip this field").
MONIKER="${MONIKER:-}"
IDENTITY="${IDENTITY:-}"
WEBSITE="${WEBSITE:-}"
SECURITY_CONTACT="${SECURITY_CONTACT:-}"
DETAILS="${DETAILS:-}"

# Gas/fees.
GAS="${GAS:-auto}"
GAS_ADJUSTMENT="${GAS_ADJUSTMENT:-1.5}"
GAS_PRICES="${GAS_PRICES:-0.00000000000000001aaion}"

# true = don't ask for confirmation before signing/broadcasting.
AUTO_CONFIRM="${AUTO_CONFIRM:-false}"

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

if [[ -z "$COMMISSION_RATE" && -z "$MONIKER" && -z "$IDENTITY" && -z "$WEBSITE" \
      && -z "$SECURITY_CONTACT" && -z "$DETAILS" ]]; then
  echo "Nothing to edit — set at least one of COMMISSION_RATE, MONIKER, IDENTITY,"
  echo "WEBSITE, SECURITY_CONTACT or DETAILS. Example:"
  echo "  COMMISSION_RATE=0.08 $0"
  exit 1
fi

echo ">> Config: chain-id=$CHAIN_ID from=$FROM_KEY${COMMISSION_RATE:+ commission-rate=$COMMISSION_RATE}"

# ---------------------------------------------------------------------------
# Build the edit-validator tx
# ---------------------------------------------------------------------------

CMD=(
  "$BINARY" --home "$HOME_DIR" tx staking edit-validator
  --from "$FROM_KEY"
  --keyring-backend "$KEYRING_BACKEND"
  --chain-id "$CHAIN_ID"
  --gas "$GAS"
  --gas-adjustment "$GAS_ADJUSTMENT"
  --gas-prices "$GAS_PRICES"
  --node "$NODE_RPC"
)

[[ -n "$COMMISSION_RATE" ]] && CMD+=(--commission-rate "$COMMISSION_RATE")
[[ -n "$MONIKER" ]] && CMD+=(--moniker "$MONIKER")
[[ -n "$IDENTITY" ]] && CMD+=(--identity "$IDENTITY")
[[ -n "$WEBSITE" ]] && CMD+=(--website "$WEBSITE")
[[ -n "$SECURITY_CONTACT" ]] && CMD+=(--security-contact "$SECURITY_CONTACT")
[[ -n "$DETAILS" ]] && CMD+=(--details "$DETAILS")
[[ "$AUTO_CONFIRM" == "true" ]] && CMD+=(--yes)

"${CMD[@]}"
