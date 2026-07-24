package evmd

import (
	"context"

	"github.com/ethereum/go-ethereum/common"

	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/types/module"
	upgradetypes "github.com/cosmos/cosmos-sdk/x/upgrade/types"

	erc20types "github.com/cosmos/evm/x/erc20/types"
)

// UpgradeName defines the on-chain upgrade name for registering the native
// AION token (base denom "aaion") as an ERC20-compatible (WERC20) precompile,
// so it can be used with the standard ERC20 interface (transfer, balanceOf,
// approve, etc.) from contracts and tooling such as ethers.js.
const UpgradeName = "v1.1.0-register-waion"

// WAIONPrecompileAddress is the address at which the AION native token is
// exposed as an ERC20/WERC20-compatible precompile. Chosen to follow the
// existing static precompile numbering (staking/bank/gov/... occupy
// 0x...0800-0807); this is the next free slot. This address becomes the
// permanent on-chain identity of "wrapped AION" once the upgrade runs -
// treat it as immutable after launch.
const WAIONPrecompileAddress = "0x0000000000000000000000000000000000000900"

func (app EVMD) RegisterUpgradeHandlers() {
	app.UpgradeKeeper.SetUpgradeHandler(
		UpgradeName,
		func(ctx context.Context, _ upgradetypes.Plan, fromVM module.VersionMap) (module.VersionMap, error) {
			sdkCtx := sdk.UnwrapSDKContext(ctx)

			pair := erc20types.TokenPair{
				Erc20Address:  WAIONPrecompileAddress,
				Denom:         "aaion",
				Enabled:       true,
				ContractOwner: erc20types.OWNER_MODULE,
			}
			if err := app.Erc20Keeper.SetToken(sdkCtx, pair); err != nil {
				return nil, err
			}
			if err := app.Erc20Keeper.EnableNativePrecompile(sdkCtx, common.HexToAddress(WAIONPrecompileAddress)); err != nil {
				return nil, err
			}

			return app.ModuleManager.RunMigrations(ctx, app.Configurator(), fromVM)
		},
	)

	upgradeInfo, err := app.UpgradeKeeper.ReadUpgradeInfoFromDisk()
	if err != nil {
		panic(err)
	}

	if upgradeInfo.Name == UpgradeName && !app.UpgradeKeeper.IsSkipHeight(upgradeInfo.Height) {
		storeUpgrades := storetypes.StoreUpgrades{
			Added: []string{},
		}
		// configure store loader that checks if version == upgradeHeight and applies store upgrades
		app.SetStoreLoader(upgradetypes.UpgradeStoreLoader(upgradeInfo.Height, &storeUpgrades))
	}
}
