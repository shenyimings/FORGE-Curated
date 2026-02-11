// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { BridgeCoordinator } from "./coordinator/BridgeCoordinator.sol";
import { IERC20Mintable } from "./interfaces/IERC20Mintable.sol";
import { IWhitelabeledUnit } from "./interfaces/IWhitelabeledUnit.sol";

/**
 * @title BridgeCoordinatorL2
 * @notice L2-specific implementation of bridge coordinator that burns/mints units instead of transferring
 * @dev Extends BridgeCoordinator with proper token lifecycle management for L2 deployments.
 * Burns units when bridging out and mints units when bridging in, maintaining total supply consistency.
 */
contract BridgeCoordinatorL2 is BridgeCoordinator {
    using SafeERC20 for IERC20;

    /**
     * @notice Burns units when bridging out from L2
     * @dev Overrides base implementation to burn units
     * @param whitelabel The whitelabeled unit token address, or zero address for native unit token
     * @param owner The address that owns the units to be burned
     * @param amount The amount of units to burn
     */
    function _restrictUnits(address whitelabel, address owner, uint256 amount) internal override {
        if (whitelabel == address(0)) {
            IERC20Mintable(genericUnit).burn(owner, address(this), amount);
        } else {
            IWhitelabeledUnit(whitelabel).unwrap(owner, address(this), amount);
            IERC20Mintable(genericUnit).burn(address(this), address(this), amount);
        }

        // Note: Burn would fail if unwrapping did not transfer the correct amount
    }

    /**
     * @notice Mints units when bridging in to L2
     * @dev Overrides base implementation to mint new units
     * @param whitelabel The whitelabeled unit token address, or zero address for native unit token
     * @param receiver The address that should receive the newly minted units
     * @param amount The amount of units to mint
     */
    function _releaseUnits(address whitelabel, address receiver, uint256 amount) internal override {
        if (whitelabel == address(0)) {
            IERC20Mintable(genericUnit).mint(receiver, amount);
        } else {
            IERC20Mintable(genericUnit).mint(address(this), amount);
            IERC20(genericUnit).forceApprove(address(whitelabel), amount);
            IWhitelabeledUnit(whitelabel).wrap(receiver, amount);
        }
    }
}
