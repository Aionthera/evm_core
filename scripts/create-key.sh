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

KEYRING_BACKEND="${KEYRING_BACKEND:-file}"
KEYRING_PASSPHRASE="${KEYRING_PASSPHRASE:-}"

KEY_NAME="${KEY_NAME:-my-account}"

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

if [[ "$KEYRING_BACKEND" == "file" && -n "$KEYRING_PASSPHRASE" ]]; then
  printf '%s\n%s\n' "$KEYRING_PASSPHRASE" "$KEYRING_PASSPHRASE" |
    "$BINARY" --home "$HOME_DIR" keys add "$KEY_NAME" --keyring-backend "$KEYRING_BACKEND" 2>&1
else
  "$BINARY" --home "$HOME_DIR" keys add "$KEY_NAME" --keyring-backend "$KEYRING_BACKEND" 2>&1
fi

echo "Private key (0x):"
run_keyring_cmd "$BINARY" --home "$HOME_DIR" keys unsafe-export-eth-key "$KEY_NAME" --keyring-backend "$KEYRING_BACKEND" | sed 's/^/0x/'

echo
read -rp "Save the mnemonic and private key, then press ENTER to continue..."

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
echo "======================================================================"
