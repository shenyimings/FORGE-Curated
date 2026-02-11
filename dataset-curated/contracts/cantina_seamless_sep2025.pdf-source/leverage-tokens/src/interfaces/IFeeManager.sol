// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILeverageToken} from "./ILeverageToken.sol";
import {ExternalAction} from "src/types/DataTypes.sol";

interface IFeeManager {
    /// @notice Error emitted when `FEE_MANAGER_ROLE` tries to set fee higher than `MAX_FEE`
    /// @param fee The fee that was set
    /// @param maxFee The maximum fee that can be set
    error FeeTooHigh(uint256 fee, uint256 maxFee);

    /// @notice Error emitted when trying to set the treasury address to the zero address
    error ZeroAddressTreasury();

    /// @notice Emitted when the default management fee for new LeverageTokens is updated
    /// @param fee The default management fee for new LeverageTokens, 100_00 is 100%
    event DefaultManagementFeeAtCreationSet(uint256 fee);

    /// @notice Emitted when a LeverageToken fee is set for a specific action
    /// @param leverageToken The LeverageToken that the fee was set for
    /// @param action The action that the fee was set for
    /// @param fee The fee that was set
    event LeverageTokenActionFeeSet(ILeverageToken indexed leverageToken, ExternalAction indexed action, uint256 fee);

    /// @notice Emitted when the management fee is charged for a LeverageToken
    /// @param leverageToken The LeverageToken that the management fee was charged for
    /// @param sharesFee The amount of shares that were minted to the treasury
    event ManagementFeeCharged(ILeverageToken indexed leverageToken, uint256 sharesFee);

    /// @notice Emitted when the management fee is set
    /// @param token The LeverageToken that the management fee was set for
    /// @param fee The fee that was set
    event ManagementFeeSet(ILeverageToken indexed token, uint256 fee);

    /// @notice Emitted when a treasury fee is set for a specific action
    /// @param action The action that the fee was set for
    /// @param fee The fee that was set
    event TreasuryActionFeeSet(ExternalAction indexed action, uint256 fee);

    /// @notice Emitted when the treasury address is set
    /// @param treasury The address of the treasury
    event TreasurySet(address treasury);

    /// @notice Function that charges any accrued management fees for the LeverageToken by minting shares to the treasury
    /// @param token LeverageToken to charge management fee for
    /// @dev If the treasury is not set, the management fee is not charged (shares are not minted to the treasury) but
    /// still accrues
    function chargeManagementFee(ILeverageToken token) external;

    /// @notice Returns the default management fee for new LeverageTokens
    /// @return fee The default management fee for new LeverageTokens, 100_00 is 100%
    function getDefaultManagementFeeAtCreation() external view returns (uint256 fee);

    /// @notice Returns the total supply of the LeverageToken adjusted for any accrued management fees
    /// @param token LeverageToken to get fee adjusted total supply for
    /// @return totalSupply Fee adjusted total supply of the LeverageToken
    function getFeeAdjustedTotalSupply(ILeverageToken token) external view returns (uint256 totalSupply);

    /// @notice Returns the timestamp of the most recent management fee accrual for a LeverageToken
    /// @param leverageToken The LeverageToken to get the timestamp for
    /// @return timestamp The timestamp of the most recent management fee accrual
    function getLastManagementFeeAccrualTimestamp(ILeverageToken leverageToken)
        external
        view
        returns (uint120 timestamp);

    /// @notice Returns the LeverageToken fee for a specific action
    /// @param leverageToken The LeverageToken to get fee for
    /// @param action The action to get fee for
    /// @return fee Fee for action, 100_00 is 100%
    function getLeverageTokenActionFee(ILeverageToken leverageToken, ExternalAction action)
        external
        view
        returns (uint256 fee);

    /// @notice Returns the management fee for a LeverageToken
    /// @param token LeverageToken to get management fee for
    /// @return fee Management fee for the LeverageToken, 100_00 is 100%
    function getManagementFee(ILeverageToken token) external view returns (uint256 fee);

    /// @notice Returns the address of the treasury
    /// @return treasury The address of the treasury
    function getTreasury() external view returns (address treasury);

    /// @notice Returns the treasury fee for a specific action
    /// @param action Action to get fee for
    /// @return fee Fee for action, 100_00 is 100%
    function getTreasuryActionFee(ExternalAction action) external view returns (uint256 fee);

    /// @notice Sets the default management fee for new LeverageTokens
    /// @param fee The default management fee for new LeverageTokens, 100_00 is 100%
    /// @dev Only `FEE_MANAGER_ROLE` can call this function
    function setDefaultManagementFeeAtCreation(uint256 fee) external;

    /// @notice Sets the management fee for a LeverageToken
    /// @param token LeverageToken to set management fee for
    /// @param fee Management fee, 100_00 is 100%
    /// @dev Only `FEE_MANAGER_ROLE` can call this function
    function setManagementFee(ILeverageToken token, uint256 fee) external;

    /// @notice Sets the address of the treasury. The treasury receives all treasury and management fees from the
    /// LeverageManager.
    /// @param treasury The address of the treasury
    /// @dev Only `FEE_MANAGER_ROLE` can call this function
    function setTreasury(address treasury) external;

    /// @notice Sets the treasury fee for a specific action
    /// @param action The action to set fee for
    /// @param fee The fee for action, 100_00 is 100%
    /// @dev Only `FEE_MANAGER_ROLE` can call this function.
    function setTreasuryActionFee(ExternalAction action, uint256 fee) external;
}
