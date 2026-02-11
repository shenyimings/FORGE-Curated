// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

/// @title IRebalanceAdapterBase
/// @notice Interface for the base RebalanceAdapter
/// @dev This is minimal interface required for the RebalanceAdapter to be used by the LeverageManager
interface IRebalanceAdapterBase {
    /// @notice Returns the initial collateral ratio for a LeverageToken
    /// @param token LeverageToken to get initial collateral ratio for
    /// @return initialCollateralRatio Initial collateral ratio for the LeverageToken
    /// @dev Initial collateral ratio is followed when the LeverageToken has no shares and on deposits when debt is 0.
    function getLeverageTokenInitialCollateralRatio(ILeverageToken token)
        external
        view
        returns (uint256 initialCollateralRatio);

    /// @notice Validates if a LeverageToken is eligible for rebalance
    /// @param token LeverageToken to check eligibility for
    /// @param state State of the LeverageToken
    /// @param caller Caller of the function
    /// @return isEligible True if LeverageToken is eligible for rebalance, false otherwise
    function isEligibleForRebalance(ILeverageToken token, LeverageTokenState memory state, address caller)
        external
        view
        returns (bool isEligible);

    /// @notice Validates if the LeverageToken's state after rebalance is valid
    /// @param token LeverageToken to validate state for
    /// @param stateBefore State of the LeverageToken before rebalance
    /// @return isValid True if state after rebalance is valid, false otherwise
    function isStateAfterRebalanceValid(ILeverageToken token, LeverageTokenState memory stateBefore)
        external
        view
        returns (bool isValid);

    /// @notice Post-LeverageToken creation hook. Used for any validation logic or initialization after a LeverageToken
    /// is created using this adapter
    /// @param creator The address of the creator of the LeverageToken
    /// @param leverageToken The address of the LeverageToken that was created
    /// @dev This function is called in `LeverageManager.createNewLeverageToken` after the new LeverageToken is created
    function postLeverageTokenCreation(address creator, address leverageToken) external;
}
