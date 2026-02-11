// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {USDTForkTest} from "liquidity-base/test/fork/USDTForkTest.t.sol";
import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";

/**
 * @title USDT Mainnet Fork Testing
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract USDTMainnetForkTest is USDTForkTest, ALTBCTestSetup {
    function setUp() public {
        _setUp(address(0xdAC17F958D2ee523a2206206994597C13D831ec7), "ETHEREUM_RPC_KEY");
    }
}

/**
 * @title USDT Polygon Fork Testing
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract USDTPolygonForkTest is USDTForkTest, ALTBCTestSetup {
    function setUp() public {
        _setUp(address(0xc2132D05D31c914a87C6611C10748AEb04B58e8F), "POLYGON_RPC_KEY");
    }
}
