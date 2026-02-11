// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title WeightStrategy
/// @notice Abstract contract for weight strategies that determine the target weights of assets in a basket.
/// @dev This contract should be implemented by strategies that provide specific logic for calculating target weights.
/// Use cases include:
/// - `AutomaticWeightStrategy.sol`: Calculates weights based on external market data or other on-chain data sources.
/// - `ManagedWeightStrategy.sol`: Allows manual setting of target weights by an authorized manager.
/// The sum of the weights returned by `getTargetWeights` should be 1e18.
abstract contract WeightStrategy {
    /// @notice Returns the target weights for the assets in the basket that the rebalancing process aims to achieve.
    /// @param bitFlag The bit flag representing a list of assets.
    /// @return targetWeights The target weights of the assets in the basket. The weights should sum to 1e18.
    function getTargetWeights(uint256 bitFlag) public view virtual returns (uint64[] memory targetWeights);

    /// @notice Checks whether the strategy supports the given bit flag, representing a list of assets.
    /// @param bitFlag The bit flag representing a list of assets.
    /// @return supported A boolean indicating whether the strategy supports the given bit flag.
    function supportsBitFlag(uint256 bitFlag) public view virtual returns (bool supported);
}
