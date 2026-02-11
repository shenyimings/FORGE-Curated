// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract RecoverFunds {
    using SafeERC20 for IERC20;

    /// @notice Recover assets to the asset recoverer
    /// @param assets The address of the assets to recover
    function recoverAssets(address[] calldata assets) external {
        uint256 length = assets.length;
        for (uint256 i; i < length; ++i) {
            IERC20(assets[i]).safeTransfer(_assetRecoverer(), _assetRecoverableAmount(assets[i]));
        }
    }

    /// @notice The address who will receive locked funds
    /// @return The address to which the recovered assets will be sent
    function _assetRecoverer() internal virtual returns (address);

    /// @notice Overridable function to check whether an asset can be safely recovered without breaking other contract's
    /// invariants
    /// @param token The address of the token to recover
    /// @return The amount of tokens that can be recovered (0 if the token cannot be recovered)
    function _assetRecoverableAmount(address token) internal view virtual returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Gap for upgradeability
    uint256[50] private __gap;
}
