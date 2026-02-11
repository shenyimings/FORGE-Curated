// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/**
 * @notice Safely attempts to retrieve the decimal places of an ERC20 token
 * @dev Uses a low-level staticcall to avoid reverting if the token doesn't implement decimals()
 * or if the implementation is non-standard. Validates that the returned value fits in uint8.
 * @param asset_ The ERC20 token contract to query
 * @return ok True if the decimals were successfully retrieved and are valid, false otherwise
 * @return assetDecimals The number of decimal places for the token (0-255), or 0 if retrieval failed
 */
function tryGetAssetDecimals(IERC20 asset_) view returns (bool ok, uint8 assetDecimals) {
    (bool success, bytes memory encodedDecimals) =
        address(asset_).staticcall(abi.encodeCall(IERC20Metadata.decimals, ()));
    if (success && encodedDecimals.length >= 32) {
        uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
        if (returnedDecimals <= type(uint8).max) {
            // casting to 'uint8' is safe because 'returnedDecimals' is guaranteed to be less than or equal to
            // 'type(uint8).max'
            // forge-lint: disable-next-line(unsafe-typecast)
            return (true, uint8(returnedDecimals));
        }
    }
    return (false, 0);
}
