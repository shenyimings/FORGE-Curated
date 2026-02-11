// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = pool.withdrawRevenue.selector;
        selectors[1] = pool.enableSwaps.selector;
        selectors[2] = pool.setLPFee.selector;
        targetContract(address(pool));
        targetSelector(FuzzSelector({addr: address(pool), selectors: selectors}));
        targetSender(alice);
        vm.startPrank(admin);
        (uint expected, , ) = pool.simSwap(address(yToken), 1_000_000_000_000_000_000);
        pool.swap(address(yToken), 1_000_000_000_000_000_000, expected, msg.sender, getValidExpiration());

        _startingXLiquidity = IERC20(pool.xToken()).balanceOf(address(pool));
        _startingYLiquidity = IERC20(pool.yToken()).balanceOf(address(pool));
    }

    function invariant_verifyRevertsForNotOwner_enableSwaps() public view {
        assertFalse(pool.paused());
    }

    function invariant_verifyRevertsForNotOwner_setLPFee() public view {
        (uint16 fee, , , , ) = pool.getFeeInfo();
        assertEq(fee, 30);
    }
}
