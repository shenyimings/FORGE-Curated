/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {USDCForkTest} from "liquidity-base/test/fork/USDCForkTest.t.sol";
import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";

/**
 * @title USDC Mainnet Fork Testing
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
contract ALTBCUSDCMainnetForkTest is USDCForkTest, ALTBCTestSetup {
    function setUp() public {
        _setUp(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), "ETHEREUM_RPC_KEY");
    }
}

/**
 * @title USDC Polygon Fork Testing
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
contract ALTBCUSDCPolygonForkTest is USDCForkTest, ALTBCTestSetup {
    function setUp() public {
        _setUp(address(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359), "POLYGON_RPC_KEY");
    }
}
