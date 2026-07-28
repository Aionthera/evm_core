#!/usr/bin/env bash
#
# Submits a governance proposal to update the feemarket MinGasPrice parameter
# on a live Aionthera chain, then votes yes immediately.
#
# With a single validator the proposal passes as soon as the voting period ends
# (48 h normal, 24 h expedited). Use EXPEDITED=true (default) to cut it to 24 h.
#
# Usage:
#   ./scripts/update-gas-price.sh
#
# Override any variable with an env-var prefix:
#   MIN_GAS_PRICE=5000000000 ./scripts/update-gas-price.sh

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
NODE_RPC="${NODE_RPC:-tcp://localhost:26657}"

KEYRING_BACKEND="${KEYRING_BACKEND:-file}"
KEYRING_PASSPHRASE="${KEYRING_PASSPHRASE:-}"
FROM_KEY="${FROM_KEY:-validator}"

# Gas price to set (in aaion, 18 decimals). Default: 1 Gwei = 1_000_000_000 aaion
MIN_GAS_PRICE="${MIN_GAS_PRICE:-1000000000}"

# true = expedited proposal (24 h voting) — requires 50_000_000 aaion deposit.
# false = normal proposal (48 h voting) — requires 10_000_000 aaion deposit.
EXPEDITED="${EXPEDITED:-true}"

GAS="${GAS:-auto}"
GAS_ADJUSTMENT="${GAS_ADJUSTMENT:-1.5}"
TX_FEES="${TX_FEES:-1000000aaion}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() { echo ">> $*"; }

run_keyring_cmd() {
  if [[ "$KEYRING_BACKEND" == "file" && -n "$KEYRING_PASSPHRASE" ]]; then
    printf '%s\n' "$KEYRING_PASSPHRASE" | "$@"
  else
    "$@"
  fi
}

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

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found. Install it before continuing (e.g. pacman -S jq / apt install jq)."
  exit 1
fi

# ---------------------------------------------------------------------------
# Key check
# ---------------------------------------------------------------------------

log "Checking keyring for '$FROM_KEY'..."
if ! run_keyring_cmd "$BINARY" --home "$HOME_DIR" keys show "$FROM_KEY" \
     --keyring-backend "$KEYRING_BACKEND" >/dev/null 2>&1; then
  echo
  echo "Key '$FROM_KEY' not found in keyring. Import it first:"
  echo "  IMPORT_MODE=hex ./scripts/import-key.sh"
  echo "  # or"
  echo "  IMPORT_MODE=mnemonic ./scripts/import-key.sh"
  exit 1
fi

ADDR="$(run_keyring_cmd "$BINARY" --home "$HOME_DIR" keys show "$FROM_KEY" -a \
        --keyring-backend "$KEYRING_BACKEND")"
log "Signing address: $ADDR"

# ---------------------------------------------------------------------------
# Balance check
# ---------------------------------------------------------------------------

REQUIRED_DEPOSIT=$( [[ "$EXPEDITED" == "true" ]] && echo "50000000" || echo "10000000" )

log "Checking balance (need at least ${REQUIRED_DEPOSIT}aaion for deposit)..."
BALANCE_JSON="$("$BINARY" --home "$HOME_DIR" query bank balances "$ADDR" \
                --node "$NODE_RPC" -o json 2>/dev/null)"
BALANCE="$(echo "$BALANCE_JSON" | jq -r '.balances[] | select(.denom=="aaion") | .amount' 2>/dev/null || echo "0")"
BALANCE="${BALANCE:-0}"

log "Balance: ${BALANCE}aaion"

if (( BALANCE < REQUIRED_DEPOSIT )); then
  echo "Insufficient balance for deposit. Have ${BALANCE}aaion, need ${REQUIRED_DEPOSIT}aaion."
  exit 1
fi

# ---------------------------------------------------------------------------
# Build proposal
# ---------------------------------------------------------------------------

DEPOSIT="${REQUIRED_DEPOSIT}aaion"
PROPOSAL_FILE="$(mktemp /tmp/gas-price-proposal-XXXXXX.json)"
trap 'rm -f "$PROPOSAL_FILE"' EXIT

MIN_GAS_PRICE_DEC="${MIN_GAS_PRICE}.000000000000000000"

cat > "$PROPOSAL_FILE" << EOF
{
  "messages": [
    {
      "@type": "/cosmos.params.v1beta1.ParameterChangeProposal",
      "title": "Set MinGasPrice to ${MIN_GAS_PRICE}",
      "description": "Update feemarket MinGasPrice to ${MIN_GAS_PRICE} aaion ($(( MIN_GAS_PRICE / 1000000000 )) Gwei).",
      "changes": [
        {
          "subspace": "feemarket",
          "key": "MinGasPrice",
          "value": "\"${MIN_GAS_PRICE_DEC}\""
        }
      ]
    }
  ],
  "metadata": "",
  "deposit": "${DEPOSIT}",
  "title": "Set MinGasPrice to ${MIN_GAS_PRICE}",
  "summary": "Update feemarket MinGasPrice to ${MIN_GAS_PRICE} aaion.",
  "expedited": $( [[ "$EXPEDITED" == "true" ]] && echo "true" || echo "false" )
}
EOF

log "Proposal preview:"
cat "$PROPOSAL_FILE"
echo

# ---------------------------------------------------------------------------
# Submit proposal
# ---------------------------------------------------------------------------

log "Submitting proposal..."
TX_OUTPUT="$(run_keyring_cmd "$BINARY" --home "$HOME_DIR" tx gov submit-proposal "$PROPOSAL_FILE" \
  --from "$FROM_KEY" \
  --chain-id "$CHAIN_ID" \
  --node "$NODE_RPC" \
  --keyring-backend "$KEYRING_BACKEND" \
  --gas "$GAS" \
  --gas-adjustment "$GAS_ADJUSTMENT" \
  --fees "$TX_FEES" \
  --yes \
  -o json 2>&1)"

echo "$TX_OUTPUT" | jq . 2>/dev/null || echo "$TX_OUTPUT"

TX_HASH="$(echo "$TX_OUTPUT" | jq -r '.txhash' 2>/dev/null || true)"
if [[ -z "$TX_HASH" || "$TX_HASH" == "null" ]]; then
  echo "Could not extract tx hash — check the output above for errors."
  exit 1
fi

log "Tx submitted: $TX_HASH"
log "Waiting 6 seconds for the tx to be included in a block..."
sleep 6

# ---------------------------------------------------------------------------
# Get proposal ID
# ---------------------------------------------------------------------------

PROPOSAL_ID="$("$BINARY" --home "$HOME_DIR" query gov proposals \
  --node "$NODE_RPC" -o json 2>/dev/null \
  | jq -r '[.proposals[] | select(.status=="PROPOSAL_STATUS_DEPOSIT_PERIOD" or .status=="PROPOSAL_STATUS_VOTING_PERIOD")] | last | .id' \
  2>/dev/null || true)"

if [[ -z "$PROPOSAL_ID" || "$PROPOSAL_ID" == "null" ]]; then
  echo "Could not auto-detect proposal ID. List proposals with:"
  echo "  $BINARY --home $HOME_DIR query gov proposals --node $NODE_RPC"
  echo "Then vote manually:"
  echo "  $BINARY --home $HOME_DIR tx gov vote <ID> yes --from $FROM_KEY --chain-id $CHAIN_ID --fees $TX_FEES"
  exit 1
fi

log "Proposal ID: $PROPOSAL_ID"

# ---------------------------------------------------------------------------
# Vote yes
# ---------------------------------------------------------------------------

log "Voting yes on proposal $PROPOSAL_ID..."
run_keyring_cmd "$BINARY" --home "$HOME_DIR" tx gov vote "$PROPOSAL_ID" yes \
  --from "$FROM_KEY" \
  --chain-id "$CHAIN_ID" \
  --node "$NODE_RPC" \
  --keyring-backend "$KEYRING_BACKEND" \
  --fees "$TX_FEES" \
  --yes \
  -o json | jq -r '.txhash' | xargs -I{} echo ">> Vote tx: {}"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

VOTING_PERIOD=$( [[ "$EXPEDITED" == "true" ]] && echo "24h" || echo "48h" )

echo
echo "======================================================================"
echo "Proposal #${PROPOSAL_ID} submitted and voted YES."
echo "MinGasPrice will be set to ${MIN_GAS_PRICE} aaion after the voting"
echo "period ends (~${VOTING_PERIOD} from now)."
echo
echo "Check status anytime with:"
echo "  $BINARY --home $HOME_DIR query gov proposal $PROPOSAL_ID --node $NODE_RPC"
echo "======================================================================"
