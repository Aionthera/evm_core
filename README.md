# Aionthera

Own blockchain, compatible with MetaMask, Solidity and the whole standard EVM tooling (Hardhat, Foundry, etc.), built as a sovereign **Cosmos SDK + EVM** chain (via [`cosmos/evm`](https://github.com/cosmos/evm), successor to Ethermint).

- **Native token (gas/staking):** AION (base denom `aaion`, 18 decimal places)
- **Consensus:** CometBFT (Cosmos SDK) — 100% sovereign chain, no recurring fee to any third-party network
- **Address prefix:** `aionthera1...`
- **Chain ID:** `aionthera_78912-1` (EIP-155 `78912` for the EVM side)
- **Environment:** development on Windows, node running on a remote Linux VPS

## Token economics

The genesis allocation (see `INITIAL_BALANCE` in `scripts/init-chain.sh`) is only the starting point, **not a supply cap**. Total AION supply grows over time and is not fixed:

- **Inflation (`x/mint`):** every block, the standard Cosmos SDK mint module (`evmd/genesis.go`, wired in `evmd/app.go`) creates new AION and credits it to the `FeeCollector` module account. This is genuinely new supply, not a transfer of existing coins. Params are the Cosmos SDK defaults (inflation targets ~7–20%/year, adjusting toward a 67% bonded ratio) unless customized in genesis.
- **Gas fees (EIP-1559 via `x/feemarket`):** transaction fees split into base fee + priority tip, but **unlike Ethereum L1, the base fee is not burned**. The full fee amount is sent to `FeeCollector` (`evm/x/vm/keeper/fees.go`) just like the tip.
- **Distribution (`x/distribution`):** at the end of each block, everything accumulated in `FeeCollector` (new inflation + full gas fees) is paid out to validators and delegators proportional to stake, minus validator commission.

In short: validators/delegators are paid from two sources — freshly minted AION (inflation) plus 100% of transaction fees — and neither is burned, so circulating supply only increases. Reaching a fixed/deflationary supply (e.g. zeroing mint params and/or burning the base fee) would require explicit customization not present in this fork today.

## WAION (wrapped AION)

**WAION isn't a separate token — there's no separate supply, no locking, no minting.** It's just the name given to an ERC20-shaped *view* over the exact same AION balance, so Solidity contracts and standard EVM tooling (wallets, DEXs, DeFi protocols expecting an ERC20) can read/move AION through the interface they already know (`transfer`, `balanceOf`, `approve`, ...). AION continues to live only as a Cosmos SDK bank balance; WAION is just the bridge that exposes it as an ERC20.

- **Mechanism:** [WERC20 precompile](evm/precompiles/werc20/README.md) — a WETH-style interface (`deposit`, `withdraw`, `transfer`, `balanceOf`, ...) over the native token. `deposit`/`withdraw` don't actually move or lock anything; they exist only for interface compatibility with WETH-style contracts. Every WAION balance/transfer is really just the underlying AION balance/transfer, seen through the precompile.
- **Address:** `0x0000000000000000000000000000000000000900` (`WAIONPrecompileAddress`, `evm/evmd/upgrades.go`), configurable via `WAION_PRECOMPILE_ADDRESS` in `scripts/init-chain.sh`.
- **Registration:** for chains initialized from scratch, via `NewErc20GenesisState` in `evm/evmd/genesis.go`; on the already-running Aionthera chain, via the `v1.1.0-register-waion` upgrade handler in `evm/evmd/upgrades.go`.
- **Decimals:** `aaion` already uses 18 decimal places on the Cosmos SDK side (see Token economics above), matching the EVM side 1:1 — no precision conversion needed, unlike chains where the bank denom uses fewer decimals.
