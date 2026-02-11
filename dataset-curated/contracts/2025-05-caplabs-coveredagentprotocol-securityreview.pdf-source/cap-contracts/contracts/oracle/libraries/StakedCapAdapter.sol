// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IOracle } from "../../interfaces/IOracle.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Staked Cap Token Adapter
/// @notice Prices are calculated based on the underlying cap token price and accrued yield
library StakedCapAdapter {
    /// @notice Fetch price for a staked cap token
    /// @param _asset Staked cap token address
    /// @return latestAnswer Price of the staked cap token fixed to 8 decimals
    /// @return lastUpdated Last updated timestamp
    function price(address _asset) external view returns (uint256 latestAnswer, uint256 lastUpdated) {
        address capToken = IERC4626(_asset).asset();
        (latestAnswer, lastUpdated) = IOracle(msg.sender).getPrice(capToken);
        uint256 capTokenDecimals = 10 ** IERC20Metadata(capToken).decimals();
        uint256 pricePerFullShare = IERC4626(_asset).convertToAssets(capTokenDecimals);
        latestAnswer = latestAnswer * pricePerFullShare / capTokenDecimals;
    }
}
