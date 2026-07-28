package aionthera

import (
	"github.com/ethereum/go-ethereum/common/hexutil"

	"github.com/cosmos/evm/rpc/backend"

	"cosmossdk.io/log/v2"
)

// PublicAPI exposes Aionthera-specific node information.
type PublicAPI struct {
	logger  log.Logger
	backend backend.EVMBackend
}

// NewPublicAPI creates a new Aionthera API instance.
func NewPublicAPI(logger log.Logger, backend backend.EVMBackend) *PublicAPI {
	return &PublicAPI{
		logger:  logger.With("module", "aionthera"),
		backend: backend,
	}
}

// PoolPriceLimit returns the minimum gas price enforced by the EVM txpool (price-limit in app.toml).
func (api *PublicAPI) PoolPriceLimit() hexutil.Uint64 {
	api.logger.Debug("aionthera_poolPriceLimit")
	return hexutil.Uint64(api.backend.GetConfig().JSONRPC.PriceLimit)
}
