// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library SwapPathLib {
    /// @notice Encode the path as required by the Aerodrome Slipstream router
    function _encodeAerodromeSlipstreamPath(address[] memory path, int24[] memory tickSpacing, bool reverseOrder)
        internal
        pure
        returns (bytes memory encodedPath)
    {
        if (reverseOrder) {
            encodedPath = abi.encodePacked(path[path.length - 1]);
            for (uint256 i = tickSpacing.length; i > 0; i--) {
                uint256 indexToAppend = i - 1;
                encodedPath = abi.encodePacked(encodedPath, tickSpacing[indexToAppend], path[indexToAppend]);
            }
        } else {
            encodedPath = abi.encodePacked(path[0]);
            for (uint256 i = 0; i < tickSpacing.length; i++) {
                encodedPath = abi.encodePacked(encodedPath, tickSpacing[i], path[i + 1]);
            }
        }
    }

    /// @notice Encode the path as required by the Uniswap V3 router
    function _encodeUniswapV3Path(address[] memory path, uint24[] memory fees, bool reverseOrder)
        internal
        pure
        returns (bytes memory encodedPath)
    {
        if (reverseOrder) {
            encodedPath = abi.encodePacked(path[path.length - 1]);
            for (uint256 i = fees.length; i > 0; i--) {
                uint256 indexToAppend = i - 1;
                encodedPath = abi.encodePacked(encodedPath, fees[indexToAppend], path[indexToAppend]);
            }
        } else {
            encodedPath = abi.encodePacked(path[0]);
            for (uint256 i = 0; i < fees.length; i++) {
                encodedPath = abi.encodePacked(encodedPath, fees[i], path[i + 1]);
            }
        }
    }
}
