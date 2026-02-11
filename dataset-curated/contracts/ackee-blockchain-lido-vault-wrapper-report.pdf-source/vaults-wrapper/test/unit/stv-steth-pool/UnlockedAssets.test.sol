// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {Test} from "forge-std/Test.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";

contract UnlockedAssetsTest is Test, SetupStvStETHPool {
    uint256 ethToDeposit = 4 ether;

    function setUp() public override {
        super.setUp();
        pool.depositETH{value: ethToDeposit}(address(this), address(0));
    }

    // unlockedAssetsOf tests

    function test_UnlockedAssets_EqualsTotal_WhenNoMinted() public view {
        uint256 totalAssets = pool.assetsOf(address(this));
        uint256 unlockedAssets = pool.unlockedAssetsOf(address(this));

        assertEq(unlockedAssets, totalAssets);
    }

    function test_UnlockedAssets_DecreasesAfterMinting() public {
        uint256 unlockedBefore = pool.unlockedAssetsOf(address(this));
        uint256 wstethToMint = 1 * 10 ** 18;

        pool.mintWsteth(wstethToMint);

        uint256 unlockedAfter = pool.unlockedAssetsOf(address(this));
        assertLt(unlockedAfter, unlockedBefore);
    }

    function test_UnlockedAssets_ZeroWhenFullyMinted() public {
        uint256 maxCapacity = pool.remainingMintingCapacitySharesOf(address(this), 0);

        pool.mintWsteth(maxCapacity);

        assertEq(pool.unlockedAssetsOf(address(this)), 0);
    }

    function test_UnlockedAssets_IncreasesAfterBurning() public {
        uint256 wstethToMint = 1 * 10 ** 18;
        pool.mintWsteth(wstethToMint);
        wsteth.approve(address(pool), type(uint256).max);

        uint256 unlockedBefore = pool.unlockedAssetsOf(address(this));

        pool.burnWsteth(wstethToMint / 2);

        uint256 unlockedAfter = pool.unlockedAssetsOf(address(this));
        assertGt(unlockedAfter, unlockedBefore);
    }

    function test_UnlockedAssets_WithBurnParameter_Calculated() public {
        uint256 wstethToMint = 2 * 10 ** 18;
        pool.mintWsteth(wstethToMint);

        uint256 sharesToBurn = 1 * 10 ** 18;
        uint256 unlockedWithBurn = pool.unlockedAssetsOf(address(this), sharesToBurn);
        uint256 unlockedWithoutBurn = pool.unlockedAssetsOf(address(this), 0);

        assertGt(unlockedWithBurn, unlockedWithoutBurn);
    }

    // unlockedStvOf tests

    function test_UnlockedStv_EqualsBalance_WhenNoMinted() public view {
        uint256 balance = pool.balanceOf(address(this));
        uint256 unlockedStv = pool.unlockedStvOf(address(this));

        assertEq(unlockedStv, balance);
    }

    function test_UnlockedStv_DecreasesAfterMinting() public {
        uint256 unlockedBefore = pool.unlockedStvOf(address(this));
        uint256 wstethToMint = 1 * 10 ** 18;

        pool.mintWsteth(wstethToMint);

        uint256 unlockedAfter = pool.unlockedStvOf(address(this));
        assertLt(unlockedAfter, unlockedBefore);
    }

    function test_UnlockedStv_ConversionFromAssets_Accurate() public view {
        uint256 unlockedAssets = pool.unlockedAssetsOf(address(this));
        uint256 unlockedStv = pool.unlockedStvOf(address(this));

        uint256 expectedStv = unlockedAssets * pool.totalSupply() / pool.totalAssets();

        assertEq(unlockedStv, expectedStv);
    }

    function test_UnlockedStv_WithBurnParameter_Calculated() public {
        uint256 wstethToMint = 2 * 10 ** 18;
        pool.mintWsteth(wstethToMint);

        uint256 sharesToBurn = 1 * 10 ** 18;
        uint256 unlockedWithBurn = pool.unlockedStvOf(address(this), sharesToBurn);
        uint256 unlockedWithoutBurn = pool.unlockedStvOf(address(this), 0);

        assertGt(unlockedWithBurn, unlockedWithoutBurn);
    }

    // stethSharesToBurnForStvOf tests

    function test_SharesToBurn_ZeroForZeroStv() public view {
        assertEq(pool.stethSharesToBurnForStvOf(address(this), 0), 0);
    }

    function test_SharesToBurn_CalculatesCorrectAmount() public {
        uint256 wstethToMint = 2 * 10 ** 18;
        pool.mintWsteth(wstethToMint);

        // Try to unlock most of the balance (80%) - this requires burning shares
        uint256 stvToUnlock = (pool.balanceOf(address(this)) * 80) / 100;
        uint256 sharesToBurn = pool.stethSharesToBurnForStvOf(address(this), stvToUnlock);

        assertGt(sharesToBurn, 0);
    }

    function test_SharesToBurn_RevertOn_InsufficientBalance() public {
        uint256 balance = pool.balanceOf(address(this));
        uint256 excessiveStv = balance + 1;

        vm.expectRevert(StvStETHPool.InsufficientBalance.selector);
        pool.stethSharesToBurnForStvOf(address(this), excessiveStv);
    }

    function test_SharesToBurn_ForFullBalance() public {
        uint256 wstethToMint = 2 * 10 ** 18;
        pool.mintWsteth(wstethToMint);

        uint256 fullBalance = pool.balanceOf(address(this));
        uint256 sharesToBurn = pool.stethSharesToBurnForStvOf(address(this), fullBalance);

        assertEq(sharesToBurn, pool.mintedStethSharesOf(address(this)));
    }
}
