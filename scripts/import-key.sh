#!/usr/bin/env bash
#
# Imports, into this computer's LOCAL keyring, a key that already exists
# elsewhere (e.g. the account with an aaion balance created on the
# production PC). Needed whenever you want to sign (request-validator.sh,
# tx send, etc.) with an account on this node, but its key was never
# created here.
#
# Usage:
#   ./scripts/import-key.sh
#
# By default it asks for the mnemonic/key interactively (safer — no secret
# ends up in an environment variable, shell history, or file).

set -euo pipefail

# ---------------------------------------------------------------------------
# Variables — edit here
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${BINARY:-$REPO_ROOT/evm/build/aiontherad}"
HOME_DIR="${HOME_DIR:-$HOME/.aiontherad}"

KEYRING_BACKEND="${KEYRING_BACKEND:-file}"

# Name this key will have in this computer's keyring (can be
# different from the name used on the original computer — it's just a
# local alias).
KEY_NAME="${KEY_NAME:-validator}"

# mnemonic | hex
#   mnemonic: recovers via the 12/24 words (what "keys add" originally showed)
#   hex:      imports the raw private key in hex (what "unsafe-export-eth-key" showed)
IMPORT_MODE="${IMPORT_MODE:-mnemonic}"

# Fill in for automation (CI, trusted scripts). Leaving it blank, the
# script asks interactively, which is the recommended path: environment
# variables holding secrets are exposed to any process from the same
# user (via /proc/<pid>/environ) and can leak into logs.
MNEMONIC="${MNEMONIC:-}"
PRIVATE_KEY_HEX="${PRIVATE_KEY_HEX:-}"

# If the "file" keyring already has a password set (or it's the first key,
# when it asks to create one), fill in to automate. Left blank, it
# stays interactive.
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

mkdir -p "$HOME_DIR"

echo ">> Importing '$KEY_NAME' (mode: $IMPORT_MODE, keyring: $KEYRING_BACKEND, home: $HOME_DIR)"

# ---------------------------------------------------------------------------
# Import
# ---------------------------------------------------------------------------

case "$IMPORT_MODE" in
  mnemonic)
    if [[ -n "$MNEMONIC" ]]; then
      echo "!! MNEMONIC came via environment variable — make sure this shell/history isn't exposed."
      if [[ "$KEYRING_BACKEND" == "file" && -n "$KEYRING_PASSPHRASE" ]]; then
        printf '%s\n%s\n%s\n' "$MNEMONIC" "$KEYRING_PASSPHRASE" "$KEYRING_PASSPHRASE" |
          "$BINARY" --home "$HOME_DIR" keys add "$KEY_NAME" --recover --keyring-backend "$KEYRING_BACKEND"
      else
        printf '%s\n' "$MNEMONIC" |
          "$BINARY" --home "$HOME_DIR" keys add "$KEY_NAME" --recover --keyring-backend "$KEYRING_BACKEND"
      fi
    else
      echo ">> Paste the mnemonic when prompted (this script doesn't save it to any file)."
      "$BINARY" --home "$HOME_DIR" keys add "$KEY_NAME" --recover --keyring-backend "$KEYRING_BACKEND"
    fi
    ;;

  hex)
    if [[ -z "$PRIVATE_KEY_HEX" ]]; then
      read -r -s -p "Paste the private key in hex (won't be shown on screen): " PRIVATE_KEY_HEX
      echo
    else
      echo "!! PRIVATE_KEY_HEX came via environment variable — make sure this shell/history isn't exposed."
    fi
    echo "!! unsafe-import-eth-key receives the key as a command-line argument — this is a limitation of the CLI itself (not of this script), and it may briefly show up in 'ps aux' for other users on this machine."
    if [[ "$KEYRING_BACKEND" == "file" && -n "$KEYRING_PASSPHRASE" ]]; then
      printf '%s\n' "$KEYRING_PASSPHRASE" |
        "$BINARY" --home "$HOME_DIR" keys unsafe-import-eth-key "$KEY_NAME" "$PRIVATE_KEY_HEX" --keyring-backend "$KEYRING_BACKEND"
    else
      "$BINARY" --home "$HOME_DIR" keys unsafe-import-eth-key "$KEY_NAME" "$PRIVATE_KEY_HEX" --keyring-backend "$KEYRING_BACKEND"
    fi
    ;;

  *)
    echo "Invalid IMPORT_MODE: '$IMPORT_MODE' (use 'mnemonic' or 'hex')"
    exit 1
    ;;
esac

unset MNEMONIC PRIVATE_KEY_HEX

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------

run_keyring_cmd() {
  if [[ "$KEYRING_BACKEND" == "file" && -n "$KEYRING_PASSPHRASE" ]]; then
    printf '%s\n' "$KEYRING_PASSPHRASE" | "$@"
  else
    "$@"
  fi
}

BECH32_ADDR="$(run_keyring_cmd "$BINARY" --home "$HOME_DIR" keys show "$KEY_NAME" -a --keyring-backend "$KEYRING_BACKEND")"

echo
echo "======================================================================"
echo "Imported as '$KEY_NAME'"
echo "Address (bech32): $BECH32_ADDR"
echo "0x address:"
"$BINARY" --home "$HOME_DIR" debug addr "$BECH32_ADDR"
echo "======================================================================"
echo
echo "Check that this address matches the one that already has aaion before using it in request-validator.sh."
echo "Usage: HOME_DIR=$HOME_DIR FROM_KEY=$KEY_NAME ./scripts/request-validator.sh"
