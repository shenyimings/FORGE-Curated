// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";

/**
 * @title Test to verify the invatiant that Total Supply or either token should never change from AMM transactions.
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract LiquidityCeilingInvariants is TestCommonSetup {
    uint256 _xTotal;
    uint256 _yTotal;

    function setUp() public endWithStopPrank {
        pool = _setupPool(false);

        IERC20 tokenX = IERC20(pool.xToken());
        _xTotal = tokenX.totalSupply();

        IERC20 tokenY = IERC20(pool.yToken());
        _yTotal = tokenY.totalSupply();

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = pool.withdrawRevenue.selector;
        selectors[1] = pool.swap.selector;
        selectors[2] = pool.simSwap.selector;
        selectors[3] = pool.simSwapReversed.selector;
        selectors[4] = pool.xToken.selector;
        selectors[5] = pool.yToken.selector;
        selectors[6] = pool.enableSwaps.selector;
        selectors[7] = pool.setLPFee.selector;

        targetContract(address(pool));
        targetSelector(FuzzSelector({addr: address(pool), selectors: selectors}));
        targetSender(admin);
    }

    function invariant_TotalSupplyOfXShouldNeverChange() public view {
        IERC20 tokenX = IERC20(pool.xToken());
        uint256 updatedXTotal = tokenX.totalSupply();
        assertEq(_xTotal, updatedXTotal);
    }

    function invariant_TotalSupplyOfYShouldNeverChange() public view {
        IERC20 tokenY = IERC20(pool.yToken());
        uint256 updatedYTotal = tokenY.totalSupply();
        assertEq(_yTotal, updatedYTotal);
    }
}
