#!/usr/bin/env bash
#
# Creates a NEW account in this computer's local keyring (new mnemonic,
# new address). To bring in an account that already exists elsewhere, use
# scripts/import-key.sh instead of this one.
#
# Usage:
#   ./scripts/create-key.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Variables — edit here
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${BINARY:-$REPO_ROOT/evm/build/aiontherad}"
HOME_DIR="${HOME_DIR:-$HOME/.aiontherad}"

KEYRING_BACKEND="${KEYRING_BACKEND:-file}"
KEYRING_PASSPHRASE="${KEYRING_PASSPHRASE:-}"

KEY_NAME="${KEY_NAME:-my-account}"

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

mkdir -p "$HOME_DIR"

run_keyring_cmd() {
  if [[ "$KEYRING_BACKEND" == "file" && -n "$KEYRING_PASSPHRASE" ]]; then
    printf '%s\n' "$KEYRING_PASSPHRASE" | "$@"
  else
    "$@"
  fi
}

if "$BINARY" --home "$HOME_DIR" keys show "$KEY_NAME" --keyring-backend "$KEYRING_BACKEND" >/dev/null 2>&1; then
  echo "A key named '$KEY_NAME' already exists in this keyring ($HOME_DIR)."
  echo "Choose another KEY_NAME, or delete it first with:"
  echo "  $BINARY --home $HOME_DIR keys delete $KEY_NAME --keyring-backend $KEYRING_BACKEND"
  exit 1
fi

# ---------------------------------------------------------------------------
# keys add
# ---------------------------------------------------------------------------

echo ">> keys add $KEY_NAME (keyring: $KEYRING_BACKEND, home: $HOME_DIR)"

# The mnemonic is only shown this one time — the Cosmos SDK never writes it
# to disk. That's why the entire output (address + mnemonic) is also saved
# to a file, so you don't depend on copying it at the right moment.
KEY_INFO_FILE="$HOME_DIR/${KEY_NAME}-key-DO-NOT-SHARE.txt"

if [[ "$KEYRING_BACKEND" == "file" && -n "$KEYRING_PASSPHRASE" ]]; then
  printf '%s\n%s\n' "$KEYRING_PASSPHRASE" "$KEYRING_PASSPHRASE" |
    "$BINARY" --home "$HOME_DIR" keys add "$KEY_NAME" --keyring-backend "$KEYRING_BACKEND" 2>&1 | tee "$KEY_INFO_FILE"
else
  "$BINARY" --home "$HOME_DIR" keys add "$KEY_NAME" --keyring-backend "$KEYRING_BACKEND" 2>&1 | tee "$KEY_INFO_FILE"
fi
chmod 600 "$KEY_INFO_FILE"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

BECH32_ADDR="$(run_keyring_cmd "$BINARY" --home "$HOME_DIR" keys show "$KEY_NAME" -a --keyring-backend "$KEYRING_BACKEND")"

echo
echo "======================================================================"
echo "Key summary for '$KEY_NAME'"
echo "======================================================================"
echo "Address (bech32, account):       $BECH32_ADDR"
echo "Address (bech32, valoper):        $(run_keyring_cmd "$BINARY" --home "$HOME_DIR" keys show "$KEY_NAME" --bech val -a --keyring-backend "$KEYRING_BACKEND")"
echo "0x address (same account, for MetaMask):"
"$BINARY" --home "$HOME_DIR" debug addr "$BECH32_ADDR"
echo
echo "Mnemonic + keys add output:      $KEY_INFO_FILE"
echo "  -> copy it to a password vault and then delete it:  shred -u \"$KEY_INFO_FILE\"  (or rm -f)"
echo
echo "To import the account into MetaMask (exposes the private key in plain text):"
echo "  $BINARY --home $HOME_DIR keys unsafe-export-eth-key $KEY_NAME --keyring-backend $KEYRING_BACKEND"
echo "======================================================================"
