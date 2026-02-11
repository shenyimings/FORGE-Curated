// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ALTBCPoolCommonImpl} from "test/amm/common/ALTBCPoolCommonImpl.sol";
import {PoolPriceFuzzTest} from "liquidity-base/test/amm/common/PoolPrice.t.f.sol";
import "forge-std/console2.sol";

/**
 * @title Test Pool functionality
 * @dev fuzz test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract ALTBCPoolPriceFuzzTest is ALTBCPoolCommonImpl, PoolPriceFuzzTest {}

/**
 * @title Test Pool Stable Coin functionality
 * @dev fuzz test
 * @author @oscarsernarosero @mpetersoCode55
 */
contract PoolPriceFuzzStableCoinTest is ALTBCPoolPriceFuzzTest {
    function setUp() public endWithStopPrank {
        _setupPool(true);
    }
}

/**
 * @title Test Pool WETH functionality
 * @dev fuzz test
 * @author @oscarsernarosero @mpetersoCode55
 */
contract PoolPriceFuzzWETHTest is ALTBCPoolPriceFuzzTest {
    function setUp() public endWithStopPrank {
        _setupPool(false);
    }
}
