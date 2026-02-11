/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {WETHForkTest} from "liquidity-base/test/fork/WETHForkTest.t.sol";
import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";

/**
 * @title WETH Mainnet Fork Testing
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
contract ALTBCWETHMainnetForkTest is WETHForkTest, ALTBCTestSetup {
    function setUp() public override {
        _setUp(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), "ETHEREUM_RPC_KEY");
    }
}

/**
 * @title WETH Polygon Fork Testing
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
contract ALTBCWETHPolygonForkTest is WETHForkTest, ALTBCTestSetup {
    function setUp() public override {
        _setUp(address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619), "POLYGON_RPC_KEY");
    }
}
