// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILeverageToken} from "./ILeverageToken.sol";
import {ExternalAction} from "src/types/DataTypes.sol";

interface IFeeManager {
    /// @notice Error emitted when `FEE_MANAGER_ROLE` tries to set fee higher than `MAX_FEE`
    /// @param fee The fee that was set
    /// @param maxFee The maximum fee that can be set
    error FeeTooHigh(uint256 fee, uint256 maxFee);

    /// @notice Error emitted when trying to set a treasury fee when the treasury address is not set
    error TreasuryNotSet();

    /// @notice Emitted when a LeverageToken fee is set for a specific action
    /// @param leverageToken The LeverageToken that the fee was set for
    /// @param action The action that the fee was set for
    /// @param fee The fee that was set
    event LeverageTokenActionFeeSet(ILeverageToken indexed leverageToken, ExternalAction indexed action, uint256 fee);

    /// @notice Emitted when a treasury fee is set for a specific action
    /// @param action The action that the fee was set for
    /// @param fee The fee that was set
    event TreasuryActionFeeSet(ExternalAction indexed action, uint256 fee);

    /// @notice Emitted when the treasury address is set
    /// @param treasury The address of the treasury
    event TreasurySet(address treasury);

    /// @notice Returns the LeverageToken fee for a specific action
    /// @param leverageToken The LeverageToken to get fee for
    /// @param action The action to get fee for
    /// @return fee Fee for action, 100_00 is 100%
    function getLeverageTokenActionFee(ILeverageToken leverageToken, ExternalAction action)
        external
        view
        returns (uint256 fee);

    /// @notice Returns the address of the treasury
    /// @return treasury The address of the treasury
    function getTreasury() external view returns (address treasury);

    /// @notice Returns the treasury fee for a specific action
    /// @param action Action to get fee for
    /// @return fee Fee for action, 100_00 is 100%
    function getTreasuryActionFee(ExternalAction action) external view returns (uint256 fee);

    /// @notice Returns the max fee that can be set
    /// @return maxFee Max fee, 100_00 is 100%
    function MAX_FEE() external view returns (uint256 maxFee);

    /// @notice Sets the address of the treasury. The treasury receives all treasury fees from the LeverageManager. If the
    ///         treasury is set to the zero address, the treasury fees are reset to 0 as well
    /// @param treasury The address of the treasury
    /// @dev Only `FEE_MANAGER_ROLE` can call this function
    function setTreasury(address treasury) external;

    /// @notice Sets the treasury fee for a specific action
    /// @param action The action to set fee for
    /// @param fee The fee for action, 100_00 is 100%
    /// @dev Only `FEE_MANAGER_ROLE` can call this function.
    function setTreasuryActionFee(ExternalAction action, uint256 fee) external;
}
