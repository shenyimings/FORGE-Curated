// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OracleLibrary} from "./uniswapv0.8/OracleLibrary.sol";
import {IOracle} from "../../interfaces/IOracle.sol";

/**
 * @title UniswapV3Oracle
 * @notice For TK/ETH pool, it will return TWAP price for the last 10 mins and add 5% slippage
 * @dev This price will be used in whitelist contract to calculate the ETH tokenIn amount.
 * The actual amount could be different because, the ticks used at the time of purchase won't be the same as this TWAP
 */
contract UniswapV3Oracle is IOracle {
    /// @notice TWAP period
    uint32 public constant PERIOD = 10 minutes;
    /// @notice Will calculate 1 TK price in ETH
    uint128 public constant BASE_AMOUNT = 1e18; // TK has 18 decimals

    /// @notice TK/WETH pair
    address public immutable pool;
    /// @notice TK token address
    address public immutable baseToken;
    /// @notice WETH token address
    address public immutable WETH;

    constructor(address _pool, address _baseToken, address _WETH) {
        pool = _pool;
        baseToken = _baseToken;
        WETH = _WETH;
    }

    /// @notice Returns TK/WETH Univ3TWAP
    function name() external pure returns (string memory) {
        return "TK/WETH Univ3TWAP";
    }

    /// @notice Returns TWAP price for 1 TK for the last 10 mins
    function peek(uint256 baseAmount) external view returns (uint256) {
        uint32 longestPeriod = OracleLibrary.getOldestObservationSecondsAgo(pool);
        uint32 period = PERIOD < longestPeriod ? PERIOD : longestPeriod;
        int24 tick = OracleLibrary.consult(pool, period);
        uint256 quotedWETHAmount = OracleLibrary.getQuoteAtTick(tick, BASE_AMOUNT, baseToken, WETH);
        // Apply 5% slippage
        return (quotedWETHAmount * baseAmount * 95) / 1e20; // 100 / 1e18
    }
}
