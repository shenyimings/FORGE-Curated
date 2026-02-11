/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";

/**
 * @title Test all invariants in relation to adding liquidity to the pool.
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract AddingLiquidityInvariants is TestCommonSetup {
    uint xTokenLiquidity;
    uint yTokenLiquidity;

    function setUp() public endWithStopPrank {
        pool = _setupPool(false);
        uint amountToTrade = 50_000 * ERC20_DECIMALS;

        vm.startPrank(admin);
        (uint _expected, , ) = pool.simSwap(pool.yToken(), amountToTrade);
        pool.swap(pool.yToken(), amountToTrade, _expected);
        xTokenLiquidity = pool.xTokenLiquidity();
        yTokenLiquidity = pool.yTokenLiquidity();
        vm.startPrank(admin);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PoolBase(address(pool)).addXSupply.selector;
        targetContract(address(pool));
        targetSelector(FuzzSelector({addr: address(pool), selectors: selectors}));
        targetSender(admin);
    }

    function invariant_liquidityCanNeverDecreaseCallingAddLiquidity_TokenX() public startAsAdmin {
        assertGe(pool.xTokenLiquidity(), xTokenLiquidity);
    }

    function invariant_liquidityCanNeverDecreaseCallingAddLiquidity_TokenY() public view {
        assertGe(pool.yTokenLiquidity(), yTokenLiquidity);
    }

    function invariant_liquidityCanNeverIncreasePastMaxSupply() public {
        uint maxTokenSupply = _getMaxXTokenSupply();
        assertLe(pool.xTokenLiquidity(), maxTokenSupply);
    }
}
