/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console2.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPoolEvents} from "src/common/IEvents.sol";
import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import {GenericERC20} from "src/example/ERC20/GenericERC20.sol";

/**
 * @title Test Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract PoolPartialFundingTest is TestCommonSetup {
    function setUp() public endWithStopPrank {
        pool = _setupPoolPartialFunding(false);
    }

    function testLiquidity_Pool_initializePartialXSupply_Positive() public {
        uint maxSupply = _getMaxXTokenSupply();

        uint poolBalance = xToken.balanceOf(address(pool));

        assertGt(maxSupply, poolBalance);
    }

    function testLiquidity_Pool_topUpXSupply_Positive() public startAsAdmin endWithStopPrank {
        uint poolBalanceBefore = xToken.balanceOf(address(pool));
        uint addAmount = X_TOKEN_MAX_SUPPLY / 2;
        pool.addXSupply(addAmount);
        uint poolBalanceAfter = xToken.balanceOf(address(pool));

        assertNotEq(poolBalanceAfter, poolBalanceBefore);
        assertEq(poolBalanceBefore + addAmount, poolBalanceAfter);
    }

    function testLiquidity_Pool_topUpXSupply_NotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vm.prank(alice);
        pool.addXSupply(X_TOKEN_MAX_SUPPLY / 2);
    }

    function testLiquidity_Pool_topUpXSupply_ExceedMaxX() public startAsAdmin {
        uint addAmount = X_TOKEN_MAX_SUPPLY / 2 + 1;
        IERC20(pool.xToken()).approve(address(pool), addAmount);
        vm.expectRevert(abi.encodeWithSignature("XOutOfBounds(uint256)", 1));
        pool.addXSupply(addAmount);
    }

    function testLiquidity_Pool_topUpXSupply_ExceedMaxXOutstandingX() public startAsAdmin {
        uint addAmount = X_TOKEN_MAX_SUPPLY / 2;
        uint amountIn = 1e18;
        IERC20 _yToken = IERC20(pool.yToken());

        // perform a swap to move x token out of the contract
        (uint expected, , ) = pool.simSwap(address(_yToken), amountIn);
        pool.swap(address(_yToken), amountIn, expected - 300);
        IERC20(pool.xToken()).approve(address(pool), addAmount + 1);
        vm.expectRevert(abi.encodeWithSignature("XOutOfBounds(uint256)", 1));
        pool.addXSupply(addAmount + 1);
    }

    function testLiquidity_Pool_tradePartialXSupply_Positive() public startAsAdmin endWithStopPrank {
        uint256 previous;
        uint256 amountIn = 2 * 1e7 * ERC20_DECIMALS;
        uint256 startingLiquidity = pool.xTokenLiquidity();
        uint256 totalOut;
        uint counter;
        IERC20 _yToken = IERC20(pool.yToken());

        while (totalOut < startingLiquidity) {
            (uint expected, uint expectedFeeAmount, ) = pool.simSwap(address(_yToken), amountIn);
            if (expected > pool.xTokenLiquidity()) break;

            vm.expectEmit(true, true, true, true, address(pool));
            emit IPoolEvents.Swap(address(_yToken), amountIn, expected, expected);
            (uint actual, uint actualFeeAmount, ) = pool.swap(address(_yToken), amountIn, expected);
            counter++;

            assertEq(actual, expected);
            assertEq(expectedFeeAmount, actualFeeAmount);

            previous = actual;
            totalOut += actual;
        }
    }

    function testLiquidity_Pool_tradePartialXSupply_ExceedXBalance() public startAsAdmin endWithStopPrank {
        uint256 startingLiquidity = pool.xTokenLiquidity();
        IERC20 _yToken = IERC20(pool.yToken());
        (uint amountIn, , ) = pool.simSwapReversed(address(xToken), startingLiquidity);

        pool.swap(address(_yToken), amountIn, startingLiquidity - 1); // -1 for rounding issues.

        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", address(pool), 1, 335487624690070233));
        pool.swap(address(_yToken), ERC20_DECIMALS, 100000);
    }

    function testLiquidity_Pool_tradeFullXSupply_Positive() public startAsAdmin endWithStopPrank {
        uint256 startingLiquidity = pool.xTokenLiquidity();
        IERC20 _yToken = IERC20(pool.yToken());

        (uint amountIn, , ) = pool.simSwapReversed(address(xToken), startingLiquidity);
        GenericERC20(address(_yToken)).mint(admin, amountIn);
        pool.swap(address(_yToken), amountIn, startingLiquidity - 1); // -1 for rounding issues.

        (uint256 expectedOut, , ) = pool.simSwap(address(_yToken), ERC20_DECIMALS);
        vm.expectRevert(abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", address(pool), 1, 335487624690070233));
        pool.swap(address(_yToken), ERC20_DECIMALS, expectedOut);

        pool.addXSupply(X_TOKEN_MAX_SUPPLY / 2);

        uint256 afterAddingLiquidity = pool.xTokenLiquidity();
        (expectedOut, , ) = pool.simSwap(address(_yToken), ERC20_DECIMALS);
        (uint amountOut, , ) = pool.swap(address(_yToken), ERC20_DECIMALS, expectedOut);
        uint256 afterSwapLiquidity = pool.xTokenLiquidity();

        assertEq(afterAddingLiquidity, amountOut + afterSwapLiquidity);
    }
}
