# Scripts — Aionthera

Quick reference for which script to run in each situation. All of them are
idempotent enough to re-read before running — but if in doubt, read the
script's header (`head -n 20 scripts/<name>.sh`) before executing.

Conventions common to all scripts:

- Configurable via environment variable (`CHAIN_ID`, `HOME_DIR`, `KEY_NAME`,
  etc.) — run `VAR=value ./scripts/something.sh`. The defaults appear at the
  top of each file.
- `BINARY` default: `evm/build/aiontherad`. If it doesn't exist yet, the
  scripts compile it automatically (`make -C evm build`) before continuing.
- `HOME_DIR` default: `~/.aiontherad`. If you run more than one node/validator
  on the same machine, use different `HOME_DIR` values to avoid collisions.
- Secrets (mnemonic, private key) are requested interactively by
  default — avoid passing them via environment variable outside of trusted
  automation.

## Dependencies

The scripts (and the `make -C evm build` they run automatically when the
binary is missing — which also runs `setup-go-env.sh` first, see below) need:
`go`, a C compiler + `make` (`CGO_ENABLED=1` is required by the Cosmos SDK),
`git`, `curl` and `jq`.

`backup-node.sh`/`restore-node.sh` additionally need `gpg` — the encryption
passphrase is prompted for directly in the shell (or fed via
`BACKUP_PASSPHRASE`), not via `gpg`'s own pinentry, so no `pinentry` package
is required.

### Keeping Go's cache out of `~/`

By default Go writes its module cache (`GOMODCACHE`) and build cache
(`GOCACHE`) under `~/go` and `~/.cache/go-build`, which can grow to a few GB
per machine. `setup-go-env.sh` points those at `.go/` inside the repo
checkout instead (handy on small disks or shared boxes):

```bash
./scripts/setup-go-env.sh
```

Every script that builds the binary automatically (`make -C evm build`) runs
this first, so you don't need to call it yourself before the usual
scenarios below — it's only useful to run standalone if you want the cache
relocated before the first build, or on a machine where you'll build `evm`
by hand outside these scripts.

`.go/` is already in `.gitignore`. This is a per-user `go env` setting, not
repo-specific config, so it applies to any Go project built on that machine
afterward — it's idempotent, so re-running it (e.g. once per script
invocation) is harmless.

### Arch Linux

```bash
sudo pacman -Syu
sudo pacman -S --needed go base-devel git curl jq gnupg
```

`base-devel` provides `gcc`/`make`/etc. Check `go version` against `evm/go.mod`
after cloning — if the repo's Arch package is behind the minimum required, get
a newer one from the AUR (e.g. `yay -S go1.22`) or install manually into
`/usr/local/go`.

### NixOS

There's no package manager install step — either drop into a temporary shell
with everything needed:

```bash
nix-shell -p go gcc gnumake git curl jq gnupg
```

or, for something that persists across reboots/reconnects, add to
`/etc/nixos/configuration.nix`:

```nix
environment.systemPackages = with pkgs; [ go gcc gnumake git curl jq gnupg ];
```

and run `sudo nixos-rebuild switch`. `make`/`gcc` are not present by default
outside a devshell or explicit package list — that's why a plain
`./scripts/init-chain.sh` fails with `make: command not found` on a bare
NixOS install.

Both `backup-node.sh` and `restore-node.sh` prompt for the passphrase
directly in the shell (hidden input) and feed it to
`gpg --batch --pinentry-mode loopback`, so this works the same over a plain
SSH session with no GUI/pinentry setup. For trusted automation, skip the
prompt by setting `BACKUP_PASSPHRASE`:

```bash
BACKUP_PASSPHRASE='strong_password' ./scripts/backup-node.sh
BACKUP_PASSPHRASE='strong_password' ./scripts/restore-node.sh /path/backup.tar.gz.gpg
```

## Cross-compiling for other platforms

The scripts only run `aiontherad` for the OS/arch of the machine they're
executed on (`evm/build/aiontherad`, no suffix). To produce binaries for
other platforms — e.g. building release artifacts on Linux to distribute to
Windows or ARM64 machines — use the cross-compile targets in `evm/Makefile`
directly. Since `CGO_ENABLED=0` for these builds, no target-platform C
toolchain is required; the host machine's Go toolchain cross-compiles
everything.

```bash
cd evm

make build-linux-amd64    # build/aiontherad-linux-amd64
make build-linux-arm64    # build/aiontherad-linux-arm64
make build-windows-amd64  # build/aiontherad-windows-amd64.exe
make build-windows-arm64  # build/aiontherad-windows-arm64.exe

# or all four at once:
make build-release
```

`make build-linux` is an alias for `build-linux-amd64`, and `make
build-windows` for `build-windows-amd64` (the amd64 variant of each OS is
the common case). To run one of these cross-compiled binaries with the
`scripts/*.sh` above, point `BINARY` at it explicitly instead of relying on
the default:

```bash
BINARY=evm/build/aiontherad-linux-arm64 ./scripts/init-chain.sh
```

## Index

| Scenario | Situation | Scripts, in order |
|---|---|---|
| [1. Chain from scratch](#1-chain-from-scratch) | First chain, network doesn't exist yet | `init-chain.sh` → `start-chain.sh` |
| [2. Existing chain](#2-existing-chain) | Join as a full node on a network that's already running | `join-network.sh` → `start-chain.sh` |
| [3. New validator](#3-new-validator) | Node synced, account with balance, no `create-validator` yet | `create-key.sh` (or `import-key.sh`) → `request-validator.sh` |
| [4. Existing validator](#4-existing-validator) | Recover/move a validator that already exists on-chain | `backup-node.sh` / `restore-node.sh` (+ `import-key.sh`) |

---

## 1. Chain from scratch

You are creating the Aionthera network for the first time (new genesis, block 0).
This only makes sense to run **once**, at the original creation of the chain.

```bash
cd evm && make build
cd ..
./scripts/init-chain.sh
./scripts/start-chain.sh
```

What `init-chain.sh` does:

1. `aiontherad init` — creates `HOME_DIR`, generates `priv_validator_key.json` and `node_key.json`.
2. `keys add` — creates the validator account (the mnemonic and private key are
   **shown only this once**, then the script pauses so you can save them before continuing).
3. `add-genesis-account` + `gentx` + `collect-gentxs` — grants the account an
   initial balance and registers it as a validator directly in the genesis.
4. Adjusts the genesis `denom_metadata` (required, otherwise `start` panics).
5. Adjusts `config.toml` (`mempool.type = app`) and `app.toml` (`json-rpc.enable = true`).

**After running:**

- Run [`backup-node.sh`](#4-existing-validator) and move the backup off
  this machine — it's the only moment `priv_validator_key.json` exists
  anywhere.

---

## 2. Existing chain

You want to bring up a **new full node** pointing at an Aionthera network that
is already running in production (does not generate a new genesis).

```bash
cd evm && make build
cd ..

CHAIN_ID=aionthera_78912-1 ./scripts/join-network.sh

./scripts/start-chain.sh
```

`GENESIS_SOURCE` defaults to the `genesis.json` published in this repo
([`network/genesis.json`](../network/genesis.json), fetched from
`raw.githubusercontent.com`) — only set it explicitly if you want a different
source (a local path or another node's endpoint).

Unless `PERSISTENT_PEERS` is already set as an environment variable, the
script asks for a seed `node_id` and `host:port` interactively, defaulting to
this project's own seed node (`seed1.aionthera.org`) — press Enter twice to
accept the defaults, or type a different node/host (e.g. to point at a peer
other than the public seed).

What `join-network.sh` does:

1. `aiontherad init` — generates **new** `priv_validator_key.json`/`node_key.json`
   (this specific node's identity, does not inherit anything from another node).
2. Downloads/copies the network's real `genesis.json` and checks that the `chain_id` matches.
3. Configures `persistent_peers` in `config.toml`.
4. Same mandatory adjustments as `init-chain.sh` (mempool, json-rpc).

**After syncing** (`catching_up: false`), this node is just a full node
— it only becomes a validator if you follow scenario 3.

---

## P2P configuration — sentry + validator

When the network has a **sentry node** (full node that exposes JSON-RPC to the
backend/internet) and a **validator** (signs blocks, not exposed directly),
the default Tendermint/CometBFT P2P settings cause the connection to drop
repeatedly and transactions to get stuck in the sentry's mempool.

### Why the default config breaks

| Default | Problem |
|---|---|
| `addr_book_strict = true` | Only saves publicly-routable IPs to the address book. Private IPs (192.168.x.x, 10.x.x.x) are never saved → address book stays empty → Peer Exchange (PEX) behaves erratically and interferes with the persistent connection |
| `pex = true` on validator | Validator crawls for new peers, competing with the persistent sentry connection |
| `persistent_peers` unidirectional | Only the sentry lists the validator. When the connection drops, the validator doesn't try to reconnect |
| `unconditional_peer_ids` empty | Validator can refuse the sentry's reconnection if it hits its peer limit |

The result: connection drops every ~1–2 minutes with a pong timeout, and
transactions submitted to the sentry never propagate to the validator's
mempool.

### Fix — edit `~/.aiontherad/config/config.toml` on both nodes

Get each node's ID first (run on each machine):

```bash
./aiontherad-linux-arm64 comet show-node-id
# note: Cosmos SDK v0.47+ renamed `tendermint` to `comet`
```

**Sentry node:**

```toml
[p2p]
addr_book_strict = false
pex = true
persistent_peers = "<validator_node_id>@<validator_ip>:26656"
```

If you later add external validators/peers on the sentry add the new peer to `persistent_peers`. Also set `private_peer_ids` to
the validator's node ID so the sentry never advertises the validator's address
to external peers.

**Validator:**

```toml
[p2p]
addr_book_strict = false
pex = false                         # validators should not be discoverable by the network
persistent_peers = "<sentry_node_id>@<sentry_ip>:26656"
unconditional_peer_ids = "<sentry_node_id>"   # never refuse the sentry's reconnection
```

`pex = false` on the validator is a permanent recommendation regardless of
how many nodes you add — the validator should always be behind sentries.

### Verify

After restarting both nodes:

```bash
# on sentry: should show the validator peer with is_outbound = true
curl -s http://localhost:26657/net_info | jq '.result.peers[] | {id: .node_info.id, outbound: .is_outbound}'

# on validator: should show the sentry peer with is_outbound = false (accepted inbound)
curl -s http://localhost:26657/net_info | jq '.result.peers[] | {id: .node_info.id, outbound: .is_outbound}'
```

`is_outbound: true` on the sentry and `is_outbound: false` on the validator is
the expected state — sentry initiates the connection, validator accepts it.

### Firewall check (if the connection still drops)

If the connection keeps dropping even after the config changes, check whether
`nf_conntrack` is expiring TCP connections too aggressively:

```bash
cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established
# healthy default: 432000 (5 days). Values of 60–120 will drop the P2P connection.
```

Fix:

```bash
sudo sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=432000
echo "net.netfilter.nf_conntrack_tcp_timeout_established=432000" | sudo tee -a /etc/sysctl.conf
```

---

## 3. New validator

You have a full node that's **already synced** and an account with enough
`aaion` balance, and you want to register that account as a validator for the
first time (post-genesis — different from `gentx`, which is only valid at block 0).

First, make sure the account exists in this node's keyring:

```bash
# new account (new mnemonic)
./scripts/create-key.sh

# OR an account that already exists elsewhere (e.g. already has a balance)
./scripts/import-key.sh
```

Then, with the node synced (`catching_up: false`):

```bash
HOME_DIR=~/.aiontherad \
CHAIN_ID=aionthera_78912-1 \
FROM_KEY=validator \
MONIKER="my-validator" \
./scripts/request-validator.sh
```

`request-validator.sh` builds and sends the `tx staking create-validator` tx using
this node's consensus pubkey (`comet show-validator`) and the account
provided in `FROM_KEY` as self-delegation. **This can only be done once
per operator account/address** — running it again with the same account fails
because the validator already exists.

**After creating it:** run [`backup-node.sh`](#4-existing-validator)
immediately and move the backup off this machine. From this point on,
`priv_validator_key.json` is your validator's on-chain identity — losing it
without a backup means permanently losing the ability to sign blocks with
that identity.

---

## 4. Existing validator

Situations where the validator **is already registered on-chain** (scenario 3
has already run at some point) and you need to move, recover, or switch
machines.

### 4.1 Routine backup (do this regularly, not just before touching the machine)

```bash
HOME_DIR=~/.aiontherad ./scripts/backup-node.sh
```

Generates a `.tar.gz.gpg` with `priv_validator_key.json`, `node_key.json`,
`priv_validator_state.json` and the `keyring-file/` (accounts). **Move this file
off the machine immediately** (USB drive, password vault, separate
storage) — see the detailed warnings in the script itself.

### 4.2 Restore on a new machine (e.g. reformatted PC, VPS migration)

```bash
cd evm && make build
cd ..

# 1) prepare genesis + peers (generates NEW keys, which will be overwritten in step 3)
CHAIN_ID=aionthera_78912-1 ./scripts/join-network.sh

# 2) if you only have the account mnemonic (no backup of priv_validator_key.json),
#    skip to step 3 without restore-node.sh — the old consensus key is gone anyway.
#    If you DO have the backup-node.sh backup:
./scripts/restore-node.sh /path/aionthera-backup-....tar.gz.gpg

# 3) if you didn't restore keyring-file in the step above, import the account via mnemonic:
HOME_DIR=~/.aiontherad KEY_NAME=validator ./scripts/import-key.sh

./scripts/start-chain.sh
```

`restore-node.sh` asks for explicit confirmation (`CONFIRM`) before continuing,
because restoring the same consensus key on two nodes running at the same
time causes **double-sign and slashing**. Only run this once you're certain
that the original machine/instance is powered off.

### 4.3 What to do with only the address, or only the mnemonic (no node backup)

| You have | What can be recovered |
|---|---|
| Account mnemonic + backup of `priv_validator_key.json` (via `backup-node.sh`) | Full recovery — follow 4.2. |
| Only the account mnemonic, no backup of `priv_validator_key.json` | The account and balance come back (`import-key.sh`), but the **old consensus identity is lost** — `join-network.sh` generates a new pubkey, which is not the same one already registered on-chain for that validator. Depending on the chain's Cosmos SDK version, it may be possible to rotate the existing validator's consensus key; if that's not supported, you need to undelegate everything from the old validator and, once it leaves the staking set, create a new validator (scenario 3) with the same account. |
| Only the address (bech32/0x), no mnemonic and no backup of anything | There's nothing to recover — an address alone doesn't allow signing transactions. Without the mnemonic or a copy of the keyring, the account and any balance in it are permanently inaccessible. |

After restoring/recovering, if the validator was jailed because of the
downtime:

```bash
aiontherad --home ~/.aiontherad tx slashing unjail \
  --from validator --chain-id aionthera_78912-1
```
