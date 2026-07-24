#!/usr/bin/env bash
#
# Sends the create-validator tx to an already-running Aionthera chain
# (post-genesis — different from gentx, which is only valid at block 0).
#
# Prerequisites:
#   - Your own node, already initialized (aiontherad init ...) and synced
#     with the chain, running locally or reachable via NODE_RPC.
#   - An account in the keyring with enough balance for the self-bond + fees.
#
# Usage:
#   ./scripts/request-validator.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Variables — edit here
# ---------------------------------------------------------------------------

CHAIN_ID="${CHAIN_ID:-aionthera_78912-1}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${BINARY:-$REPO_ROOT/evm/build/aiontherad}"
HOME_DIR="${HOME_DIR:-$HOME/.aiontherad}"

# RPC endpoint of the chain where the tx will be broadcast. If your local
# node is the one that's already synced, leave the default.
NODE_RPC="${NODE_RPC:-tcp://localhost:26657}"

# Account in the keyring that pays the self-bond + fees (must already have an aaion balance).
KEYRING_BACKEND="${KEYRING_BACKEND:-file}"
FROM_KEY="${FROM_KEY:-validator}"

# How much to self-delegate when creating the validator, and the minimum
# self-delegation floor (if it drops below this afterwards, the validator is
# removed from the active set).
SELF_DELEGATION_AMOUNT="${SELF_DELEGATION_AMOUNT:-1000000000000000000000aaion}"
MIN_SELF_DELEGATION="${MIN_SELF_DELEGATION:-1}"

# Commission charged on this validator's delegators' rewards.
COMMISSION_RATE="${COMMISSION_RATE:-0.10}"
COMMISSION_MAX_RATE="${COMMISSION_MAX_RATE:-0.20}"
COMMISSION_MAX_CHANGE_RATE="${COMMISSION_MAX_CHANGE_RATE:-0.01}"

# Validator's public identification.
MONIKER="${MONIKER:-my-validator}"
IDENTITY="${IDENTITY:-}"          # Keybase ID, if you have one (shows up in the explorer)
WEBSITE="${WEBSITE:-}"
SECURITY_CONTACT="${SECURITY_CONTACT:-}"
DETAILS="${DETAILS:-}"

# Gas/fees. The chain's min-gas-prices is "0aaion" by default, so 0 works,
# but keep it configurable in case that changes in the future.
GAS="${GAS:-auto}"
GAS_ADJUSTMENT="${GAS_ADJUSTMENT:-1.5}"
GAS_PRICES="${GAS_PRICES:-0aaion}"

# true = don't ask for confirmation before signing/broadcasting (careful,
# this is irreversible: the self-bond stays locked until you undelegate later).
AUTO_CONFIRM="${AUTO_CONFIRM:-false}"

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

if [[ ! -f "$HOME_DIR/config/priv_validator_key.json" ]]; then
  echo "Couldn't find $HOME_DIR/config/priv_validator_key.json"
  echo "This script assumes this node has already been initialized (aiontherad init) and is synced with the chain."
  exit 1
fi

PUBKEY="$("$BINARY" --home "$HOME_DIR" tendermint show-validator)"
echo ">> validator pubkey: $PUBKEY"

echo ">> Config: chain-id=$CHAIN_ID from=$FROM_KEY moniker=\"$MONIKER\" self-delegation=$SELF_DELEGATION_AMOUNT commission=$COMMISSION_RATE"

# ---------------------------------------------------------------------------
# Build the create-validator tx
# ---------------------------------------------------------------------------

CMD=(
  "$BINARY" --home "$HOME_DIR" tx staking create-validator
  --amount "$SELF_DELEGATION_AMOUNT"
  --pubkey "$PUBKEY"
  --moniker "$MONIKER"
  --chain-id "$CHAIN_ID"
  --commission-rate "$COMMISSION_RATE"
  --commission-max-rate "$COMMISSION_MAX_RATE"
  --commission-max-change-rate "$COMMISSION_MAX_CHANGE_RATE"
  --min-self-delegation "$MIN_SELF_DELEGATION"
  --gas "$GAS"
  --gas-adjustment "$GAS_ADJUSTMENT"
  --gas-prices "$GAS_PRICES"
  --node "$NODE_RPC"
  --from "$FROM_KEY"
  --keyring-backend "$KEYRING_BACKEND"
)

[[ -n "$IDENTITY" ]] && CMD+=(--identity "$IDENTITY")
[[ -n "$WEBSITE" ]] && CMD+=(--website "$WEBSITE")
[[ -n "$SECURITY_CONTACT" ]] && CMD+=(--security-contact "$SECURITY_CONTACT")
[[ -n "$DETAILS" ]] && CMD+=(--details "$DETAILS")
[[ "$AUTO_CONFIRM" == "true" ]] && CMD+=(--yes)

"${CMD[@]}"
