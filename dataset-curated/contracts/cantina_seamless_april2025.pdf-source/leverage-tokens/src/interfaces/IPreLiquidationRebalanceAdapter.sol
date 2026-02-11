// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Internal imports
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

interface IPreLiquidationRebalanceAdapter {
    /// @notice Emitted when the PreLiquidationRebalanceAdapter is initialized
    /// @param collateralRatioThreshold The collateral ratio threshold for pre-liquidation rebalancing. If the LeverageToken
    ///        collateral ratio is below this threshold, the LeverageToken can be pre-liquidation rebalanced
    /// @param rebalanceReward The rebalance reward percentage. The rebalance reward represents the percentage of liquidation
    ///        penalty that will be rewarded to the caller of the rebalance function. 10_000 means 100%
    event PreLiquidationRebalanceAdapterInitialized(uint256 collateralRatioThreshold, uint256 rebalanceReward);

    /// @notice Returns the LeverageManager contract
    /// @return leverageManager The LeverageManager contract
    function getLeverageManager() external view returns (ILeverageManager leverageManager);

    /// @notice Returns the collateral ratio threshold for pre-liquidation rebalancing
    /// @return collateralRatioThreshold The collateral ratio threshold for pre-liquidation rebalancing
    /// @dev When the LeverageToken collateral ratio is below this threshold, the LeverageToken can be pre-liquidation
    ///      rebalanced
    function getCollateralRatioThreshold() external view returns (uint256 collateralRatioThreshold);

    /// @notice Returns the rebalance reward percentage
    /// @return rebalanceRewardPercentage The rebalance reward percentage
    /// @dev The rebalance reward represents the percentage of liquidation cost that will be rewarded to the caller of the
    ///      rebalance function. 10000 means 100%
    function getRebalanceReward() external view returns (uint256 rebalanceRewardPercentage);

    /// @notice Returns true if the state after rebalance is valid
    /// @param token The LeverageToken
    /// @param stateBefore The state before rebalance
    /// @return isValid True if the state after rebalance is valid
    function isStateAfterRebalanceValid(ILeverageToken token, LeverageTokenState memory stateBefore)
        external
        view
        returns (bool isValid);

    /// @notice Returns true if the LeverageToken is eligible for pre-liquidation rebalance
    /// @param token The LeverageToken
    /// @param stateBefore The state before rebalance
    /// @param caller The caller of the rebalance function
    /// @return isEligible True if the LeverageToken is eligible for pre-liquidation rebalance
    /// @dev Token is eligible for pre-liquidation rebalance if health factor is below the threshold
    function isEligibleForRebalance(ILeverageToken token, LeverageTokenState memory stateBefore, address caller)
        external
        view
        returns (bool isEligible);
}
