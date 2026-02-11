// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IOracle } from "../../interfaces/IOracle.sol";
import { IVault } from "../../interfaces/IVault.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Cap Token Adapter
/// @notice Prices are calculated based on the weighted average of underlying assets
library CapTokenAdapter {
    /// @notice Fetch price for a cap token based on its underlying assets
    /// @param _asset Cap token address
    /// @return latestAnswer Price of the cap token fixed to 8 decimals
    /// @return lastUpdated Last updated timestamp
    function price(address _asset) external view returns (uint256 latestAnswer, uint256 lastUpdated) {
        uint256 capTokenSupply = IERC20Metadata(_asset).totalSupply();
        if (capTokenSupply == 0) return (1e8, block.timestamp);

        address[] memory assets = IVault(_asset).assets();
        lastUpdated = block.timestamp;

        uint256 totalUsdValue;
        lastUpdated = block.timestamp;

        for (uint256 i; i < assets.length; ++i) {
            address asset = assets[i];
            uint256 supply = IVault(_asset).totalSupplies(asset);
            uint256 supplyDecimalsPow = 10 ** IERC20Metadata(asset).decimals();
            (uint256 assetPrice, uint256 assetLastUpdated) = IOracle(msg.sender).getPrice(asset);

            totalUsdValue += supply * assetPrice / supplyDecimalsPow;
            if (assetLastUpdated < lastUpdated) lastUpdated = assetLastUpdated;
        }

        uint256 decimalsPow = 10 ** IERC20Metadata(_asset).decimals();
        latestAnswer = totalUsdValue * decimalsPow / capTokenSupply;
    }
}
