/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {SwapHandler} from "test/amm/invariants/SwapHandler.sol";
import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import "forge-std/console2.sol";
import {CumulativePrice} from "src/amm/base/CumulativePrice.sol";
/**
 * @title Test all invariants defined for the swap mechanics
 * @dev invariant test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract SwapInvariants is TestCommonSetup {
    SwapHandler _handler;
    uint256 lastFees;
    uint lastCumulativePrice;
    uint lastBlockTimestamp;
    function setUp() public endWithStopPrank {
        pool = _setupPool(false);
        _handler = new SwapHandler(pool);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = _handler.swap.selector;
        targetContract(address(_handler));
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
        targetSender(admin);
        vm.startPrank(admin);
        // Set initial X value to something above 0 before starting to swap for X
        (uint expected, , ) = pool.simSwap(address(pool.yToken()), 1_000_000_000_000_000_000);
        pool.swap(address(pool.yToken()), 1_000_000_000_000_000_000, expected);
    }
    function invariant_verifyAmountOutNeverExceedsLiquidity_TokenX() public view {
        assertLt(_handler.trackedAmountOutX(), pool.xTokenLiquidity());
    }
    function invariant_verifyFeesIncreaseTokenX() public {
        assertLt(lastFees, pool.collectedLPFees());
        lastFees = pool.collectedLPFees();
    }
    function invariant_cumulativePriceAndLastBlockTimestammpOnlyIncrease() public {
        uint cumulativePrice = CumulativePrice(address(pool)).cumulativePrice();
        uint blockTimestamp = CumulativePrice(address(pool)).lastBlockTimestamp();
        assertGt(cumulativePrice, lastCumulativePrice, "Current cumulativePrice must be greater than last cumulativePrice");
        assertGt(blockTimestamp, lastBlockTimestamp, "Current blockTimestamp must be greater than last blockTimestamp");
        lastCumulativePrice = cumulativePrice;
        lastBlockTimestamp = blockTimestamp;
    }
}
