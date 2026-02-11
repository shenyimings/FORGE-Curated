// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { SingleStrategyVault, IController, IERC20, IERC4626 } from "../../src/vault/SingleStrategyVault.sol";

contract SingleStrategyVaultHarness is SingleStrategyVault {
    constructor(
        IERC20 asset_,
        IController controller_,
        IERC4626 strategy_,
        address manager_
    )
        SingleStrategyVault(asset_, controller_, strategy_, manager_)
    { }

    function exposed_additionalOwnedAssets() external view returns (uint256) {
        return _additionalOwnedAssets();
    }

    function exposed_additionalAvailableAssets() external view returns (uint256) {
        return _additionalAvailableAssets();
    }

    function exposed_afterDeposit(uint256 assets) external {
        _afterDeposit(assets);
    }

    function exposed_beforeWithdraw(uint256 assets) external {
        _beforeWithdraw(assets);
    }
}
