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
