// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Internal imports
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

/// @title ICollateralRatiosRebalanceAdapter
/// @notice Interface for the CollateralRatiosRebalanceAdapter contract
interface ICollateralRatiosRebalanceAdapter {
    /// @notice Error thrown when min collateral ratio is too high
    error InvalidCollateralRatios();

    /// @notice Event emitted when the collateral ratios are set
    /// @param minCollateralRatio Minimum collateral ratio for the LeverageToken
    /// @param targetCollateralRatio Target collateral ratio for the LeverageToken
    /// @param maxCollateralRatio Maximum collateral ratio for the LeverageToken
    event CollateralRatiosRebalanceAdapterInitialized(
        uint256 minCollateralRatio, uint256 targetCollateralRatio, uint256 maxCollateralRatio
    );

    /// @notice Returns the LeverageManager
    /// @return leverageManager The LeverageManager
    function getLeverageManager() external view returns (ILeverageManager leverageManager);

    /// @notice Returns the minimum collateral ratio for a LeverageToken
    /// @return minCollateralRatio Minimum collateral ratio for the LeverageToken
    function getLeverageTokenMinCollateralRatio() external view returns (uint256 minCollateralRatio);

    /// @notice Returns the target collateral ratio for a LeverageToken
    /// @return targetCollateralRatio Target collateral ratio for the LeverageToken
    function getLeverageTokenTargetCollateralRatio() external view returns (uint256 targetCollateralRatio);

    /// @notice Returns the maximum collateral ratio for a LeverageToken
    /// @return maxCollateralRatio Maximum collateral ratio for the LeverageToken
    function getLeverageTokenMaxCollateralRatio() external view returns (uint256 maxCollateralRatio);

    /// @notice Returns the initial collateral ratio for a LeverageToken
    /// @return initialCollateralRatio Initial collateral ratio for the LeverageToken
    function getLeverageTokenInitialCollateralRatio(ILeverageToken token)
        external
        view
        returns (uint256 initialCollateralRatio);

    /// @notice Returns true if the LeverageToken is eligible for rebalance
    /// @param token The LeverageToken
    /// @param state The state of the LeverageToken
    /// @param caller The caller of the function
    /// @return isEligible True if the LeverageToken is eligible for rebalance, false otherwise
    function isEligibleForRebalance(ILeverageToken token, LeverageTokenState memory state, address caller)
        external
        view
        returns (bool isEligible);

    /// @notice Returns true if the LeverageToken state after rebalance is valid
    /// @param token The LeverageToken
    /// @param stateBefore The state of the LeverageToken before rebalance
    /// @return isValid True if the LeverageToken state after rebalance is valid, false otherwise
    function isStateAfterRebalanceValid(ILeverageToken token, LeverageTokenState memory stateBefore)
        external
        view
        returns (bool isValid);
}
