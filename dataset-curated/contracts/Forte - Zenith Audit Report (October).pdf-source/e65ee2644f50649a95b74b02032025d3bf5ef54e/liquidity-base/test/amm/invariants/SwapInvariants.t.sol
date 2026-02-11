// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SwapHandler} from "test/amm/invariants/SwapHandler.sol";
import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/**
 * @title Test all invariants defined for the swap mechanics
 * @dev invariant test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract SwapInvariants is TestCommonSetup {
    SwapHandler _handler;
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
        pool.swap(address(pool.yToken()), 1_000_000_000_000_000_000, expected, msg.sender, getValidExpiration());
    }
    function invariant_verifyAmountOutNeverExceedsLiquidity_TokenX() public view {
        assertLt(_handler.trackedAmountOutX(), IERC20(pool.xToken()).balanceOf(address(pool)));
    }
}
