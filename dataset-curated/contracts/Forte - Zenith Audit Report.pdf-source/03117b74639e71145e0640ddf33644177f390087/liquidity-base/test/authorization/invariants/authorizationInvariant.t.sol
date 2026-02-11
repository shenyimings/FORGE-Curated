/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";

/**
 * @title Test all invariants in relation to authorization requirements for AMM transactions.
 * @dev invariant test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract authorizationInvariants is TestCommonSetup {
    uint256 _startingXLiquidity;
    uint256 _startingYLiquidity;

    function setUp() public endWithStopPrank {
        pool = _setupPool(false);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = pool.withdrawRevenue.selector;
        selectors[1] = pool.enableSwaps.selector;
        selectors[2] = pool.setLPFee.selector;
        selectors[3] = PoolBase(address(pool)).addXSupply.selector;
        targetContract(address(pool));
        targetSelector(FuzzSelector({addr: address(pool), selectors: selectors}));
        targetSender(alice);
        vm.startPrank(admin);
        (uint expected, , ) = pool.simSwap(address(yToken), 1_000_000_000_000_000_000);
        pool.swap(address(yToken), 1_000_000_000_000_000_000, expected);

        _startingXLiquidity = pool.xTokenLiquidity();
        _startingYLiquidity = pool.yTokenLiquidity();
    }

    function invariant_verifyRevertsForNotOwner_CollectFees() public view {
        assertGt(pool.collectedLPFees(), 0);
    }

    function invariant_verifyRevertsForNotOwner_enableSwaps() public view {
        assertFalse(pool.paused());
    }

    function invariant_verifyRevertsForNotOwner_setLPFee() public view {
        assertEq(pool.lpFee(), 30);
    }

    function invariant_verifyRevertsForNotOwner_initializeXSupply_removeLiquidityXToken() public view {
        assertEq(pool.xTokenLiquidity(), _startingXLiquidity);
    }

    function invariant_verifyRevertsForNotOwner_addLiquidityYToken_removeLiquidityYToken() public view {
        assertEq(pool.yTokenLiquidity(), _startingYLiquidity);
    }
}
