#!/usr/bin/env bash
#
# Shows the bech32 and 0x (EVM) addresses for a key in the local keyring.
#
# Usage:
#   ./scripts/show-address.sh [key_name]
#
# key_name defaults to "validator" (the key created by scripts/init-chain.sh).

set -euo pipefail

KEY_NAME="${1:-validator}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${BINARY:-$REPO_ROOT/evm/build/aiontherad}"
HOME_DIR="${HOME_DIR:-$HOME/.aiontherad}"

KEYRING_BACKEND="${KEYRING_BACKEND:-file}"
KEYRING_PASSPHRASE="${KEYRING_PASSPHRASE:-}"

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

run_keyring_cmd() {
  if [[ "$KEYRING_BACKEND" == "file" && -n "$KEYRING_PASSPHRASE" ]]; then
    printf '%s\n' "$KEYRING_PASSPHRASE" | "$@"
  else
    "$@"
  fi
}

if ! run_keyring_cmd "$BINARY" --home "$HOME_DIR" keys show "$KEY_NAME" --keyring-backend "$KEYRING_BACKEND" >/dev/null 2>&1; then
  echo "No key named '$KEY_NAME' found in this keyring ($HOME_DIR, backend: $KEYRING_BACKEND)."
  echo "List existing keys with:"
  echo "  $BINARY --home $HOME_DIR keys list --keyring-backend $KEYRING_BACKEND"
  exit 1
fi

# ---------------------------------------------------------------------------
# Addresses
# ---------------------------------------------------------------------------

BECH32_ADDR="$(run_keyring_cmd "$BINARY" --home "$HOME_DIR" keys show "$KEY_NAME" -a --keyring-backend "$KEYRING_BACKEND")"
VALOPER_ADDR="$(run_keyring_cmd "$BINARY" --home "$HOME_DIR" keys show "$KEY_NAME" --bech val -a --keyring-backend "$KEYRING_BACKEND")"

echo "======================================================================"
echo "Addresses for '$KEY_NAME'"
echo "======================================================================"
echo "Address (bech32, account):  $BECH32_ADDR"
echo "Address (bech32, valoper):  $VALOPER_ADDR"
echo "0x address (EVM/MetaMask):"
"$BINARY" --home "$HOME_DIR" debug addr "$BECH32_ADDR"
echo "======================================================================"
