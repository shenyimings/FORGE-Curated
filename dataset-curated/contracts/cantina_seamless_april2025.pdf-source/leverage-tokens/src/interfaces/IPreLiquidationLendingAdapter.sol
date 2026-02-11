// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILendingAdapter} from "./ILendingAdapter.sol";

interface IPreLiquidationLendingAdapter is ILendingAdapter {
    /// @notice Returns the liquidation penalty of the position held by the lending adapter
    /// @return liquidationPenalty Liquidation penalty of the position held by the lending adapter, scaled by 1e18
    /// @dev 1e18 means that the liquidation penalty is 100%
    function getLiquidationPenalty() external view returns (uint256 liquidationPenalty);
}
