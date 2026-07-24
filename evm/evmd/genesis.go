package evmd

import (
	"encoding/json"

	testconstants "github.com/cosmos/evm/testutil/constants"
	erc20types "github.com/cosmos/evm/x/erc20/types"
	feemarkettypes "github.com/cosmos/evm/x/feemarket/types"
	evmtypes "github.com/cosmos/evm/x/vm/types"

	minttypes "github.com/cosmos/cosmos-sdk/x/mint/types"
)

// GenesisState of the blockchain is represented here as a map of raw json
// messages key'd by an identifier string.
// The identifier is used to determine which module genesis information belongs
// to so it may be appropriately routed during init chain.
// Within this application default genesis information is retrieved from
// the ModuleBasicManager which populates json from each BasicModule
// object provided to it during init.
type GenesisState map[string]json.RawMessage

// NewEVMGenesisState returns the default genesis state for the EVM module.
//
// NOTE: for the example chain implementation we need to set the default EVM denomination,
// enable ALL precompiles, and include default preinstalls.
func NewEVMGenesisState() *evmtypes.GenesisState {
	evmGenState := evmtypes.DefaultGenesisState()
	evmGenState.Params.ActiveStaticPrecompiles = evmtypes.AvailableStaticPrecompiles
	evmGenState.Preinstalls = evmtypes.DefaultPreinstalls

	return evmGenState
}

// NewErc20GenesisState returns the default genesis state for the ERC20 module.
//
// Registers the chain's native token (base denom "aaion") as a WERC20
// precompile so it is usable through the standard ERC20 interface
// (transfer, balanceOf, approve, ...). Only applies to chains initialized
// from scratch; the already-running Aionthera chain gets this via the
// "v1.1.0-register-waion" upgrade handler in upgrades.go instead.
func NewErc20GenesisState() *erc20types.GenesisState {
	erc20GenState := erc20types.DefaultGenesisState()
	erc20GenState.TokenPairs = []erc20types.TokenPair{
		{
			Erc20Address:  WAIONPrecompileAddress,
			Denom:         "aaion",
			Enabled:       true,
			ContractOwner: erc20types.OWNER_MODULE,
		},
	}
	erc20GenState.NativePrecompiles = []string{WAIONPrecompileAddress}

	return erc20GenState
}

// NewMintGenesisState returns the default genesis state for the mint module.
//
// NOTE: for the example chain implementation we are also adding a default minter.
func NewMintGenesisState() *minttypes.GenesisState {
	mintGenState := minttypes.DefaultGenesisState()

	mintGenState.Params.MintDenom = testconstants.ExampleAttoDenom
	return mintGenState
}

// NewFeeMarketGenesisState returns the default genesis state for the feemarket module.
//
// NOTE: for the example chain implementation we are disabling the base fee.
func NewFeeMarketGenesisState() *feemarkettypes.GenesisState {
	feeMarketGenState := feemarkettypes.DefaultGenesisState()
	feeMarketGenState.Params.NoBaseFee = true

	return feeMarketGenState
}
