// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { IERC20 } from ".../../lib/common/src/interfaces/IERC20.sol";
import { Upgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { MYieldFee } from "../../src/projects/yieldToAllWithFee/MYieldFee.sol";
import { MYieldToOne } from "../../src/projects/yieldToOne/MYieldToOne.sol";
import { SwapFacility } from "../../src/swap/SwapFacility.sol";

import { BaseIntegrationTest } from "../utils/BaseIntegrationTest.sol";

contract SwapFacilityIntegrationTest is BaseIntegrationTest {
    // Holds USDC, USDT and wM
    address constant USER = 0x77BAB32F75996de8075eBA62aEa7b1205cf7E004;

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 22_751_329);

        super.setUp();

        mYieldToOne = MYieldToOne(
            Upgrades.deployUUPSProxy(
                "MYieldToOne.sol:MYieldToOne",
                abi.encodeWithSelector(
                    MYieldToOne.initialize.selector,
                    NAME,
                    SYMBOL,
                    address(mToken),
                    address(swapFacility),
                    yieldRecipient,
                    admin,
                    blacklistManager,
                    yieldRecipientManager
                )
            )
        );

        _addToList(EARNERS_LIST, address(mYieldToOne));

        vm.prank(admin);
        swapFacility.grantRole(M_SWAPPER_ROLE, USER);
    }

    function test_swap() public {
        uint256 amount = 1_000_000;
        uint256 wrappedMBalanceBefore = IERC20(WRAPPED_M).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swapInM(address(mYieldToOne), amount, USER);

        assertEq(mYieldToOne.balanceOf(USER), amount);

        mYieldToOne.approve(address(swapFacility), amount);
        swapFacility.swap(address(mYieldToOne), WRAPPED_M, amount, USER);

        uint256 wrappedMBalanceAfter = IERC20(WRAPPED_M).balanceOf(USER);

        assertApproxEqAbs(wrappedMBalanceAfter, wrappedMBalanceBefore + amount, 2);
        assertEq(mYieldToOne.balanceOf(USER), 0);
    }

    function test_swapInM() public {
        uint256 amount = 1_000_000;

        assertEq(mYieldToOne.balanceOf(USER), 0);

        vm.startPrank(USER);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swapInM(address(mYieldToOne), amount, USER);

        assertEq(mYieldToOne.balanceOf(USER), amount);
    }

    function test_swapInMWithPermit_VRS() public {
        uint256 amount = 1_000_000;

        assertEq(mYieldToOne.balanceOf(USER), 0);

        vm.prank(USER);
        IERC20(address(mToken)).transfer(alice, amount);

        vm.prank(alice);
        IERC20(address(mToken)).approve(address(swapFacility), amount);

        _swapInMWithPermitVRS(address(mYieldToOne), alice, aliceKey, alice, amount, 0, block.timestamp);

        assertEq(mYieldToOne.balanceOf(alice), amount);
    }

    function test_swapOutM() public {
        uint256 amount = 1_000_000;

        vm.startPrank(USER);
        IERC20(address(mToken)).approve(address(swapFacility), amount);
        swapFacility.swapInM(address(mYieldToOne), amount, USER);

        assertEq(mYieldToOne.balanceOf(USER), amount);

        uint256 mBalanceBefore = IERC20(address(mToken)).balanceOf(USER);

        swapFacility.swapOutM(address(mYieldToOne), amount, USER);

        uint256 mBalanceAfter = IERC20(address(mToken)).balanceOf(USER);

        assertEq(mYieldToOne.balanceOf(USER), 0);
        assertEq(mBalanceAfter - mBalanceBefore, amount);
    }

    function test_swapInToken_USDC_to_wrappedM() public {
        uint256 amountIn = 1_000_000;
        uint256 minAmountOut = 997_000;

        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(USER);
        uint256 wrappedMBalanceBefore = IERC20(WRAPPED_M).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(USDC).approve(address(swapFacility), amountIn);
        swapFacility.swapInToken(USDC, amountIn, WRAPPED_M, minAmountOut, USER, "");

        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(USER);
        uint256 wrappedMBalanceAfter = IERC20(WRAPPED_M).balanceOf(USER);

        assertEq(usdcBalanceAfter, usdcBalanceBefore - amountIn);
        assertApproxEqAbs(wrappedMBalanceAfter, wrappedMBalanceBefore + amountIn, 1000);
    }

    function test_swapOutToken_wrappedM_to_USDC() public {
        uint256 amountIn = 1_000_000;
        uint256 minAmountOut = 997_000;
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(WRAPPED_M).approve(address(swapFacility), amountIn);
        swapFacility.swapOutToken(WRAPPED_M, amountIn, USDC, minAmountOut, USER, "");

        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(USER);
        assertApproxEqAbs(usdcBalanceAfter, usdcBalanceBefore + amountIn, 1000);
    }
}
