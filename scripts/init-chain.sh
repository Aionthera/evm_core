#!/usr/bin/env bash
#
# Initializes the Aionthera chain from scratch: init, validator key, genesis
# (balance + gentx), denom metadata fix and config.toml/app.toml adjustments.
#
# Usage:
#   ./scripts/init-chain.sh
#
# Run this from anywhere in the repo; the paths below are relative to the
# project root (where this script lives inside scripts/).

set -euo pipefail

# ---------------------------------------------------------------------------
# Variables — edit here
# ---------------------------------------------------------------------------

CHAIN_ID="${CHAIN_ID:-aionthera_78912-1}"
MONIKER="${MONIKER:-aionthera-validator-1}"

# Compiled binary (./scripts/build-release.sh generates the per-OS/arch
# binaries in evm/build/)
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

# Node home. Leave empty to use the default ($HOME/.aiontherad).
HOME_DIR="${HOME_DIR:-$HOME/.aiontherad}"

# Keyring backend: test | file | os
# - test: no password, only for local dev/testnet.
# - file: asks for a password; if KEYRING_PASSPHRASE is filled in below, the
#         script feeds the password automatically via stdin.
# - os:   uses the OS's native keychain (needs a daemon running).
KEYRING_BACKEND="${KEYRING_BACKEND:-file}"
KEYRING_PASSPHRASE="${KEYRING_PASSPHRASE:-}"

VALIDATOR_KEY_NAME="${VALIDATOR_KEY_NAME:-validator}"

# Denominations
BASE_DENOM="${BASE_DENOM:-aaion}"       # "on-chain" denom (18 decimals, what the EVM uses)
DISPLAY_DENOM="${DISPLAY_DENOM:-aion}"  # denom shown to humans
DENOM_EXPONENT="${DENOM_EXPONENT:-18}"
TOKEN_NAME="${TOKEN_NAME:-Aionthera}"
TOKEN_SYMBOL="${TOKEN_SYMBOL:-AION}"

# Address of the WERC20 precompile that exposes BASE_DENOM through the
# standard ERC20 interface (transfer, balanceOf, approve, ...). Must match
# WAIONPrecompileAddress in evm/evmd/upgrades.go.
WAION_PRECOMPILE_ADDRESS="${WAION_PRECOMPILE_ADDRESS:-0x0000000000000000000000000000000000000900}"

# Validator's initial balance and self-bond amount (gentx), in BASE_DENOM
INITIAL_BALANCE="${INITIAL_BALANCE:-100000000000000000000000${BASE_DENOM}}"
GENTX_STAKE_AMOUNT="${GENTX_STAKE_AMOUNT:-1000000000000000000000${BASE_DENOM}}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() { echo ">> $*"; }

run_keyring_cmd() {
  # Runs a command that may prompt for the "file" keyring password.
  # If KEYRING_PASSPHRASE is set, feeds it via stdin (once for reading,
  # twice for creation — keys add is handled separately, see below).
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

if [[ -d "$HOME_DIR" ]]; then
  echo "Home already exists at: $HOME_DIR"
  echo "This script initializes a chain from scratch and will overwrite this directory."
  read -r -p "Delete and recreate? [y/N] " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted. If you only want to reset the state (keeping keys/genesis), use:"
    echo "  $BINARY --home $HOME_DIR tendermint unsafe-reset-all"
    exit 1
  fi
  rm -rf "$HOME_DIR"
fi

log "Config: chain-id=$CHAIN_ID moniker=$MONIKER home=$HOME_DIR keyring=$KEYRING_BACKEND denom=$BASE_DENOM"

# ---------------------------------------------------------------------------
# Init + validator key
# ---------------------------------------------------------------------------

log "init"
"$BINARY" --home "$HOME_DIR" init "$MONIKER" --chain-id "$CHAIN_ID"

log "keys add $VALIDATOR_KEY_NAME"
if [[ "$KEYRING_BACKEND" == "file" && -n "$KEYRING_PASSPHRASE" ]]; then
  printf '%s\n%s\n' "$KEYRING_PASSPHRASE" "$KEYRING_PASSPHRASE" |
    "$BINARY" --home "$HOME_DIR" keys add "$VALIDATOR_KEY_NAME" --keyring-backend "$KEYRING_BACKEND" 2>&1
else
  "$BINARY" --home "$HOME_DIR" keys add "$VALIDATOR_KEY_NAME" --keyring-backend "$KEYRING_BACKEND" 2>&1
fi

echo "Private key (0x):"
run_keyring_cmd "$BINARY" --home "$HOME_DIR" keys unsafe-export-eth-key "$VALIDATOR_KEY_NAME" --keyring-backend "$KEYRING_BACKEND" | sed 's/^/0x/'

echo
read -rp "Save the mnemonic and private key, then press ENTER to continue..."
echo

# ---------------------------------------------------------------------------
# Genesis: initial balance + gentx
# ---------------------------------------------------------------------------

log "add-genesis-account"
run_keyring_cmd "$BINARY" --home "$HOME_DIR" genesis add-genesis-account \
  "$VALIDATOR_KEY_NAME" "$INITIAL_BALANCE" --keyring-backend "$KEYRING_BACKEND"

log "gentx"
run_keyring_cmd "$BINARY" --home "$HOME_DIR" genesis gentx \
  "$VALIDATOR_KEY_NAME" "$GENTX_STAKE_AMOUNT" \
  --chain-id "$CHAIN_ID" --keyring-backend "$KEYRING_BACKEND"

log "collect-gentxs"
"$BINARY" --home "$HOME_DIR" genesis collect-gentxs

# ---------------------------------------------------------------------------
# Denom metadata in the bank module (required, otherwise start panics)
# ---------------------------------------------------------------------------

log "adjusting denom_metadata in genesis"
GENESIS_FILE="$HOME_DIR/config/genesis.json"
TMP_FILE="$(mktemp)"

jq --arg base "$BASE_DENOM" \
   --arg display "$DISPLAY_DENOM" \
   --argjson exponent "$DENOM_EXPONENT" \
   --arg name "$TOKEN_NAME" \
   --arg symbol "$TOKEN_SYMBOL" \
   '.app_state.bank.denom_metadata = [{
      "description": ("The native staking and gas token of the " + $name + " chain"),
      "denom_units": [
        {"denom": $base, "exponent": 0, "aliases": []},
        {"denom": $display, "exponent": $exponent, "aliases": []}
      ],
      "base": $base,
      "display": $display,
      "name": $name,
      "symbol": $symbol
    }]' "$GENESIS_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$GENESIS_FILE"

# ---------------------------------------------------------------------------
# ERC20 module: register BASE_DENOM as a native WERC20 precompile
# ---------------------------------------------------------------------------
# NOTE: `aiontherad init` builds the default genesis from each module's own
# DefaultGenesis() via genutilcli.InitCmd(evmApp.BasicModuleManager, ...)
# (evm/evmd/cmd/evmd/cmd/root.go). It does NOT go through EVMD.DefaultGenesis()
# in evm/evmd/app.go, so the token pair set up there never reaches a
# freshly-initialized genesis.json — it has to be patched in here instead.

log "registering $BASE_DENOM as native ERC20 precompile at $WAION_PRECOMPILE_ADDRESS"

jq --arg denom "$BASE_DENOM" \
   --arg addr "$WAION_PRECOMPILE_ADDRESS" \
   '.app_state.erc20.token_pairs = [{
      "erc20_address": $addr,
      "denom": $denom,
      "enabled": true,
      "contract_owner": "OWNER_MODULE"
    }] |
    .app_state.erc20.native_precompiles = [$addr]' "$GENESIS_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$GENESIS_FILE"

# ---------------------------------------------------------------------------
# EVM module: activate the built-in static precompiles (staking, distribution,
# gov, bank, bech32, ics20, ics02, p256, slashing, vesting)
# ---------------------------------------------------------------------------
# Same root cause as above: EVMD.DefaultGenesis() is what normally sets
# app_state.evm.params.active_static_precompiles = AvailableStaticPrecompiles
# (evm/evmd/genesis.go), and `aiontherad init` never goes through it. Without
# this patch the addresses below have no code from the EVM's point of view —
# calls to them (tx or eth_call) just silently no-op instead of running the
# precompile logic, with no revert to signal it.
#
# NOTE: the module's genesis key is "evm" (x/vm/types.ModuleName = "evm"),
# NOT "vm" — despite the Go package living at x/vm. Patching .app_state.vm
# instead just creates an unused, orphaned top-level key that the chain
# never reads (validate-genesis doesn't catch it either).

log "activating static precompiles (staking, distribution, gov, bank, bech32, ics20, ics02, p256, slashing, vesting)"

jq '.app_state.evm.params.active_static_precompiles = [
      "0x0000000000000000000000000000000000000100",
      "0x0000000000000000000000000000000000000400",
      "0x0000000000000000000000000000000000000800",
      "0x0000000000000000000000000000000000000801",
      "0x0000000000000000000000000000000000000802",
      "0x0000000000000000000000000000000000000803",
      "0x0000000000000000000000000000000000000804",
      "0x0000000000000000000000000000000000000805",
      "0x0000000000000000000000000000000000000806",
      "0x0000000000000000000000000000000000000807"
    ]' "$GENESIS_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$GENESIS_FILE"

log "validate-genesis"
"$BINARY" --home "$HOME_DIR" genesis validate-genesis

# ---------------------------------------------------------------------------
# config.toml / app.toml
# ---------------------------------------------------------------------------

log "config.toml: mempool.type = app"
sed -i 's/^type = "flood"$/type = "app"/' "$HOME_DIR/config/config.toml"

log "app.toml: [json-rpc] enable = true"
sed -i '/\[json-rpc\]/,/^\[/ s/^enable = false/enable = true/' "$HOME_DIR/config/app.toml"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo
echo "======================================================================"
echo "Key summary for '$VALIDATOR_KEY_NAME'"
echo "======================================================================"

BECH32_ADDR="$(run_keyring_cmd "$BINARY" --home "$HOME_DIR" keys show "$VALIDATOR_KEY_NAME" -a --keyring-backend "$KEYRING_BACKEND")"

echo "Address (bech32, account):       $BECH32_ADDR"
echo "Address (bech32, valoper):        $(run_keyring_cmd "$BINARY" --home "$HOME_DIR" keys show "$VALIDATOR_KEY_NAME" --bech val -a --keyring-backend "$KEYRING_BACKEND")"
echo "0x address (same account, for MetaMask):"
"$BINARY" --home "$HOME_DIR" debug addr "$BECH32_ADDR"
echo
echo "======================================================================"
echo
echo "Done. To bring up the node:"
echo "  ./scripts/start-chain.sh"
