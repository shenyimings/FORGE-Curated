// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IOracle } from "./IOracle.sol";

interface IVaultAdapter {
    /// @custom:storage-location erc7201:cap.storage.VaultAdapter
    struct VaultAdapterStorage {
        mapping(address => SlopeData) slopeData;
        mapping(address => UtilizationData) utilizationData;
        uint256 maxMultiplier;
        uint256 minMultiplier;
        uint256 rate;
    }

    /// @dev Slope data for an asset
    struct SlopeData {
        uint256 kink;
        uint256 slope0;
        uint256 slope1;
    }

    /// @dev Slope data for an asset
    struct UtilizationData {
        uint256 utilizationMultiplier;
        uint256 index;
        uint256 lastUpdate;
    }

    /// @notice Fetch borrow rate for an asset from the Vault
    /// @param _vault Vault address
    /// @param _asset Asset to fetch rate for
    /// @return latestAnswer Borrow rate
    function rate(address _vault, address _asset) external returns (uint256 latestAnswer);

    /// @notice Set utilization slopes for an asset
    /// @param _asset Asset address
    /// @param _slopes Slope data
    function setSlopes(address _asset, SlopeData memory _slopes) external;

    /// @notice Set limits for the utilization multiplier
    /// @param _maxMultiplier Maximum slope multiplier
    /// @param _minMultiplier Minimum slope multiplier
    /// @param _rate Rate at which the multiplier shifts
    function setLimits(uint256 _maxMultiplier, uint256 _minMultiplier, uint256 _rate) external;
}
