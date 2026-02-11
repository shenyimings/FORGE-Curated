// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../../src/utils/ChainlinkFeedCombinator.sol";
import "../../../lib/AggregatorV3Interface.sol";


contract ChainlinkFeedCombinatorTest is Test {
  
    uint256 mainnetFork;
    ChainlinkFeedCombinator combinator;

    AggregatorV3Interface constant WSETH_ETH_FEED = AggregatorV3Interface(0xb523AE262D20A936BC152e6023996e46FDC2A95D);
    AggregatorV3Interface constant ETH_USD_FEED = AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);

    function setUp() external {
          string memory ANKR_RPC = string.concat(
            "https://rpc.ankr.com/arbitrum/",
            vm.envString("ANKR_API_KEY")
        );
        mainnetFork = vm.createFork(ANKR_RPC, 211619406);
        vm.selectFork(mainnetFork);

        combinator = new ChainlinkFeedCombinator(WSETH_ETH_FEED, ETH_USD_FEED);
    }

    function testCombinedPrice() external {
        (,int256 answer, , , ) = WSETH_ETH_FEED.latestRoundData();
        assertEq(answer, 1166051398948778600);

        (, answer, , , ) = ETH_USD_FEED.latestRoundData();
        assertEq(answer, 301900000000);

        (, answer, , , ) = combinator.latestRoundData();
        assertEq(answer, 352030917342);
    }
}
