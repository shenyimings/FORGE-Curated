// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {
    ERC4626Upgradeable,
    IERC4626
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IERC4626Vault
 * @notice Extension of the IERC4626 interface that introduces a `deposit` method with an additional referral address parameter.
 * @dev This interface enhances the standard ERC4626 vault by adding referral-based deposits.
 * @dev Also extends the VaultControl interface for managing deposit limits, deposit pause and withdrawal pause.
 */
interface IERC4626Vault is IERC4626 {
    /**
     * @notice Emitted when a deposit is made through a referral.
     * @param assets The amount of underlying tokens deposited.
     * @param receiver The address receiving the vault shares.
     * @param referral The address of the referral involved in the deposit.
     */
    event ReferralDeposit(uint256 assets, address receiver, address referral);

    /**
     * @notice Mints vault shares to the `receiver` by depositing a specified amount of `assets` with an associated `referral`.
     * @param assets The amount of underlying tokens to be deposited.
     * @param receiver The address that will receive the vault shares.
     * @param referral The address of the referral associated with the deposit.
     * @return shares The amount of vault shares minted to the `receiver`.
     *
     * @custom:requirements
     * - The `assets` to be deposited MUST be greater than 0.
     *
     * @custom:effects
     * - Transfers the underlying tokens (`assets`) from the sender to the vault.
     * - Mints the corresponding `shares` to the `receiver`.
     * - Deposits the `assets` into the underlying bond.
     * - Emits a `ReferralDeposit` event.
     */
    function deposit(uint256 assets, address receiver, address referral)
        external
        returns (uint256 shares);
}
