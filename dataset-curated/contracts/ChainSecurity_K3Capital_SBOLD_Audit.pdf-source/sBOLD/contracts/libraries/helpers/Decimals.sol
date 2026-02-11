// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Decimals
/// @notice Utility library for deriving decimals from assets.
library Decimals {
    /// @dev Returns decimals for asset on success. Defaults to 18 in case the attempt failed in some way.
    function getDecimals(address asset) internal view returns (uint8) {
        (bool success, uint8 decimals) = tryGetDecimals(asset);

        return success ? decimals : 18;
    }

    /// @dev Attempts to fetch the asset decimals. A return value of false indicates that the attempt failed in some way.
    function tryGetDecimals(address asset) internal view returns (bool, uint8) {
        (bool success, bytes memory encodedDecimals) = asset.staticcall(abi.encodeCall(IERC20Metadata.decimals, ()));

        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return (true, uint8(returnedDecimals));
            }
        }

        return (false, 0);
    }
}
