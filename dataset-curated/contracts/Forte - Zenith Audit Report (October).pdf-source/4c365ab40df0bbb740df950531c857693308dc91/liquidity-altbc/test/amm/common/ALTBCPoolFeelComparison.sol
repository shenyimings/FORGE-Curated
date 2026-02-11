// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {PoolFeeComparisonTest} from "liquidity-base/test/amm/common/PoolFeeComparison.t.sol";
import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";

/**
 * @title Test Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55
 */
contract PoolStableCoinTest is PoolFeeComparisonTest, ALTBCTestSetup {
    function setUp() public endWithStopPrank {
        _setupPool(true);
        _setUp();
    }
}

/**
 * @title Test Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55
 */
contract PoolWETHTest is PoolFeeComparisonTest, ALTBCTestSetup {
    function setUp() public endWithStopPrank {
        _setupPool(false);
        _setUp();
    }
}
