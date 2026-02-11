// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/tokens/IWSTETH.sol";
import "./EigenLayerAdapter.sol";

contract EigenLayerWstETHAdapter is EigenLayerAdapter {
    using SafeERC20 for IERC20;

    IWSTETH public immutable wsteth;
    ISTETH public immutable steth;

    constructor(
        address factory_,
        address vault_,
        IStrategyManager strategyManager_,
        IRewardsCoordinator rewardsCoordinator_,
        address wsteth_
    ) EigenLayerAdapter(factory_, vault_, strategyManager_, rewardsCoordinator_) {
        wsteth = IWSTETH(wsteth_);
        steth = wsteth.stETH();
    }

    /// @inheritdoc IProtocolAdapter
    function maxDeposit(address isolatedVault) external view override returns (uint256) {
        (, address strategy,, address withdrawalQueue) = factory.instances(isolatedVault);
        if (IEigenLayerWithdrawalQueue(withdrawalQueue).isShutdown()) {
            return 0;
        }
        if (
            IPausable(address(strategyManager)).paused(PAUSED_DEPOSITS)
                || IPausable(address(strategy)).paused(PAUSED_DEPOSITS)
                || !strategyManager.strategyIsWhitelistedForDeposit(IStrategy(strategy))
        ) {
            return 0;
        }
        (bool success, bytes memory data) =
            strategy.staticcall(abi.encodeWithSignature("getTVLLimits()"));
        if (!success) {
            return type(uint256).max;
        }
        (uint256 maxPerDeposit, uint256 maxTotalDeposits) = abi.decode(data, (uint256, uint256));
        uint256 assets = steth.balanceOf(strategy);
        if (assets >= maxTotalDeposits) {
            return 0;
        }
        uint256 stethValue = Math.min(maxPerDeposit, maxTotalDeposits - assets);
        if (stethValue > type(uint128).max) {
            return type(uint256).max;
        }
        return stethValue == 0 ? 0 : wsteth.getWstETHByStETH(stethValue);
    }

    /// @inheritdoc IProtocolAdapter
    function stakedAt(address isolatedVault) external view override returns (uint256) {
        (, address strategy,, address withdrawalQueue) = factory.instances(isolatedVault);
        if (
            !delegationManager.isDelegated(isolatedVault)
                && !IEigenLayerWithdrawalQueue(withdrawalQueue).isShutdown()
        ) {
            revert("EigenLayerWstETHAdapter: isolated vault is neither delegated nor shut down");
        }
        uint256 stethValue = IStrategy(strategy).userUnderlyingView(isolatedVault);
        return stethValue == 0 ? 0 : wsteth.getWstETHByStETH(stethValue);
    }
}
