// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/tokens/IWSTETH.sol";
import "./IsolatedEigenLayerVault.sol";

contract IsolatedEigenLayerWstETHVault is IsolatedEigenLayerVault {
    using SafeERC20 for IERC20;

    IWSTETH public immutable wsteth;
    ISTETH public immutable steth;

    constructor(address wsteth_) {
        wsteth = IWSTETH(wsteth_);
        steth = wsteth.stETH();
        _disableInitializers();
    }

    /// @inheritdoc IIsolatedEigenLayerVault
    function initialize(address vault_) external override initializer {
        require(
            address(wsteth) == IERC4626(vault_).asset(),
            "IsolatedEigenLayerWstETHVault: invalid asset"
        );
        __init_IsolatedEigenLayerVault(vault_);
    }

    /// @inheritdoc IIsolatedEigenLayerVault
    function deposit(address manager, address strategy, uint256 assets)
        external
        override
        onlyVault
    {
        if (IStrategy(strategy).underlyingToSharesView(wsteth.getStETHByWstETH(assets)) == 0) {
            // insignificant amount
            return;
        }
        IERC20(wsteth).safeTransferFrom(vault, address(this), assets);
        assets = wsteth.unwrap(assets);
        IERC20(steth).safeIncreaseAllowance(manager, assets);
        IStrategyManager(manager).depositIntoStrategy(IStrategy(strategy), steth, assets);
    }

    /// @inheritdoc IIsolatedEigenLayerVault
    function claimWithdrawal(
        IDelegationManager manager,
        IDelegationManager.Withdrawal calldata data
    ) external override returns (uint256 assets) {
        address this_ = address(this);
        (,,, address queue) = IIsolatedEigenLayerVaultFactory(factory).instances(this_);
        require(msg.sender == queue, "IsolatedEigenLayerWstETHVault: forbidden");
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(steth);
        manager.completeQueuedWithdrawal(data, tokens, 0, true);
        assets = steth.balanceOf(this_);
        IERC20(steth).safeIncreaseAllowance(address(wsteth), assets);
        assets = wsteth.wrap(assets);
        IERC20(wsteth).safeTransfer(queue, assets);
    }

    /// --------------- EXTERNAL VIEW FUNCTIONS ---------------

    function sharesToUnderlyingView(address strategy, uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        return wsteth.getWstETHByStETH(IStrategy(strategy).sharesToUnderlyingView(shares));
    }

    function underlyingToSharesView(address strategy, uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        return IStrategy(strategy).underlyingToSharesView(wsteth.getStETHByWstETH(assets));
    }
}
