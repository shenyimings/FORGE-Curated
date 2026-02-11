// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ControlledERC7575Vault, IController, IERC20 } from "../../src/vault/ControlledERC7575Vault.sol";

contract ControlledERC7575VaultHarness is ControlledERC7575Vault {
    uint256 private __additionalOwnedAssets;
    uint256 private __additionalAvailableAssets;

    struct Callback {
        bool called;
        uint256 assets;
    }

    Callback public afterDepositCallback;
    Callback public beforeWithdrawCallback;

    constructor(IERC20 asset_, IController controller_) ControlledERC7575Vault(asset_, controller_) { }

    function exposed_decimalsOffset() external view returns (uint8) {
        return _decimalsOffset;
    }

    function workaround_setAdditionalOwnedAssets(uint256 additionalOwnedAssets) external {
        __additionalOwnedAssets = additionalOwnedAssets;
    }

    function workaround_setAdditionalAvailableAssets(uint256 additionalAvailableAssets) external {
        __additionalAvailableAssets = additionalAvailableAssets;
    }

    // Override internal functions to make them accessible for testing

    function _additionalOwnedAssets() internal view override returns (uint256) {
        return __additionalOwnedAssets;
    }

    function _additionalAvailableAssets() internal view override returns (uint256) {
        return __additionalAvailableAssets;
    }

    function _afterDeposit(uint256 assets) internal override {
        afterDepositCallback.called = true;
        afterDepositCallback.assets = assets;
    }

    function _beforeWithdraw(uint256 assets) internal override {
        beforeWithdrawCallback.called = true;
        beforeWithdrawCallback.assets = assets;
    }
}
