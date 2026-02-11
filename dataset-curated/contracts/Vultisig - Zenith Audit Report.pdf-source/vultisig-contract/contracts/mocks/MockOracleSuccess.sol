// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOracle} from "../interfaces/IOracle.sol";

contract MockOracleSuccess is IOracle {
    function name() external pure returns (string memory) {
        return "TK/USDC Univ3TWAP";
    }

    // This is a simplified conversion for testing
    // In a real implementation, this would query a price oracle
    function peek(uint256 baseAmount) external pure returns (uint256) {
        // For testing, we're using a fixed rate of 1.5 USDC per token
        // For simplicity, we'll make a direct conversion regardless of decimals
        // This makes testing easier as we can use smaller numbers

        // Simple formula: 1.5 USDC per token (multiply by 3/2)
        return (baseAmount * 3) / 2;
    }
}
