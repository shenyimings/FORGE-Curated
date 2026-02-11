// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BytesLib} from "./BytesLib.sol";

/**
 * @title SwapPath Library
 * @dev Library for decoding swap path data used in DEX operations
 * @notice Provides utilities for handling different swap path formats
 */
library SwapPath {
    using BytesLib for bytes;

    /**
     * @dev Decodes generic swap path data into signature and parameters
     * @param swap_path_data Encoded swap path data
     * @return sig Function signature or identifier
     * @return data Decoded parameter data
     */
    function decode(bytes memory swap_path_data) internal pure returns (bytes32 sig, bytes memory data) {
        (sig, data) = abi.decode(swap_path_data, (bytes32, bytes));
    }

    /**
     * @dev Decodes Uniswap V2 style path data
     * @param swap_path_data Encoded token path for Uniswap V2
     * @return path Array of token addresses representing the swap path
     * @notice Used for decoding sequential token paths in Uniswap V2 style DEXs
     */
    function decodeUniswapV2Path(bytes memory swap_path_data) internal pure returns (address[] memory path) {
        path = abi.decode(swap_path_data, (address[]));
    }

    /**
     * @dev Decodes Uniswap V3 style path data
     * @param swap_path_data Encoded path data containing token addresses and fees
     * @return path Array of token addresses in the swap path
     * @return fees Array of fee tiers between each token pair
     */
    function decodeUniswapV3Path(bytes memory swap_path_data)
        internal
        pure
        returns (address[] memory path, uint24[] memory fees)
    {
        (path, fees) = abi.decode(swap_path_data, (address[], uint24[]));
    }

    function encodeUniswapV3Path(bytes memory swap_path_data) internal pure returns (bytes memory encodedPath) {
        (address[] memory path, uint24[] memory fees) = decodeUniswapV3Path(swap_path_data);
        // Initialize encoded path with first token
        encodedPath = abi.encodePacked(path[0]);

        // Encode each fee and subsequent token
        for (uint256 i = 0; i < fees.length; i++) {
            encodedPath = abi.encodePacked(encodedPath, fees[i], path[i + 1]);
        }
    }

    /**
     * @dev Gets the input token address from swap path data
     * @param isV2 Flag indicating if the path is Uniswap V2 format
     * @param swap_path_data Encoded swap path data
     * @return inputToken Address of the first token in the swap path
     * @notice Works for both Uniswap V2 and V3 path formats
     */
    function getInputToken(bytes memory swap_path_data, bool isV2) internal pure returns (address inputToken) {
        if (isV2) {
            // Extract first token from V2 path
            address[] memory path = decodeUniswapV2Path(swap_path_data);
            inputToken = path[0];
        } else {
            // Extract first token from V3 path
            (address[] memory path,) = decodeUniswapV3Path(swap_path_data);
            inputToken = path[0];
        }
    }
}
