/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolPrecisionTest} from "liquidity-base/test/amm/common/PoolPrecision.t.u.sol";
import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";

/**
 * @title Test ALTC Pool Precision functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
abstract contract ALTBCPoolPrecisionTest is PoolPrecisionTest, ALTBCTestSetup {}

contract ALTBCPoolPrecisionWithFeeTest is ALTBCPoolPrecisionTest {
    function setUp() public endWithStopPrank {
        _setUp(30);
    }
}

contract ALTBCPoolPrecisionNoFeeTest is ALTBCPoolPrecisionTest {
    function setUp() public endWithStopPrank {
        _setUp(0);
    }
}
