// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { BridgeCoordinator } from "./coordinator/BridgeCoordinator.sol";
import { PredepositCoordinator } from "./coordinator/PredepositCoordinator.sol";
import { IWhitelabeledUnit } from "./interfaces/IWhitelabeledUnit.sol";

/**
 * @title BridgeCoordinatorL1
 * @notice L1-specific BridgeCoordinator that includes predeposit functionality and handles units locking/unlocking
 * @dev Inherits from BridgeCoordinator and PredepositCoordinator to provide full bridge coordination
 * capabilities along with predeposit handling on Layer 1. Implements unit restriction and release logic
 * by transferring units to/from the coordinator contract, with support for whitelabeled units.
 */
contract BridgeCoordinatorL1 is BridgeCoordinator, PredepositCoordinator {
    using SafeERC20 for IERC20;

    /**
     * @notice Thrown when the amount of unit tokens restricted does not match the expected amount
     */
    error IncorrectEscrowBalance();

    /**
     * @notice Lock units when bridging out
     * @dev This function implements additional validation layers since whitelabel units could potentially
     * be malicious or poorly implemented.
     * @param whitelabel The whitelabeled unit token address, or zero address for native unit token
     * @param owner The address that owns the units to be restricted
     * @param amount The amount of units to restrict
     */
    function _restrictUnits(address whitelabel, address owner, uint256 amount) internal override {
        uint256 escrowBalance = IERC20(genericUnit).balanceOf(address(this));
        if (whitelabel == address(0)) {
            IERC20(genericUnit).safeTransferFrom(owner, address(this), amount);
        } else {
            IWhitelabeledUnit(whitelabel).unwrap(owner, address(this), amount);
        }

        // Note: Sanity check that the expected amount of units were actually transferred
        // Whitelabeled units could have faulty implementations that do not transfer the correct amount
        require(IERC20(genericUnit).balanceOf(address(this)) == escrowBalance + amount, IncorrectEscrowBalance());
    }

    /**
     * @notice Unlock units when bridging in
     * @param whitelabel The whitelabeled unit token address, or zero address for native unit token
     * @param receiver The address that should receive the released units
     * @param amount The amount of units to release
     */
    function _releaseUnits(address whitelabel, address receiver, uint256 amount) internal override {
        if (whitelabel == address(0)) {
            IERC20(genericUnit).safeTransfer(receiver, amount);
        } else {
            IERC20(genericUnit).forceApprove(address(whitelabel), amount);
            IWhitelabeledUnit(whitelabel).wrap(receiver, amount);
        }
    }
}
