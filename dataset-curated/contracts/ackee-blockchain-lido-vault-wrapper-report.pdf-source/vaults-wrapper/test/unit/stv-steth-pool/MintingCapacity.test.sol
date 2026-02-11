// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test} from "forge-std/Test.sol";

contract MintingCapacityTest is Test, SetupStvStETHPool {
    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 ethToDeposit = 4 ether;

    function setUp() public override {
        super.setUp();
        pool.depositETH{value: ethToDeposit}(address(this), address(0));
    }

    // totalMintingCapacitySharesOf tests

    function test_TotalMintingCapacity_BasedOnAssets() public view {
        uint256 assets = pool.assetsOf(address(this));
        uint256 expectedCapacity = pool.calcStethSharesToMintForAssets(assets);

        assertEq(pool.totalMintingCapacitySharesOf(address(this)), expectedCapacity);
    }

    function test_TotalMintingCapacity_IncreasesWithDeposits() public {
        uint256 capacityBefore = pool.totalMintingCapacitySharesOf(address(this));

        pool.depositETH{value: 1 ether}(address(this), address(0));

        uint256 capacityAfter = pool.totalMintingCapacitySharesOf(address(this));
        assertGt(capacityAfter, capacityBefore);
    }

    function test_TotalMintingCapacity_IncreasesWithRewards() public {
        uint256 capacityBefore = pool.totalMintingCapacitySharesOf(address(this));

        dashboard.mock_simulateRewards(int256(1 ether));

        uint256 capacityAfter = pool.totalMintingCapacitySharesOf(address(this));
        assertGt(capacityAfter, capacityBefore);
    }

    function test_TotalMintingCapacity_DecreasesWithLoss() public {
        uint256 capacityBefore = pool.totalMintingCapacitySharesOf(address(this));

        dashboard.mock_simulateRewards(int256(-0.5 ether));

        uint256 capacityAfter = pool.totalMintingCapacitySharesOf(address(this));
        assertLt(capacityAfter, capacityBefore);
    }

    function test_TotalMintingCapacity_ZeroForZeroAssets() public view {
        assertEq(pool.totalMintingCapacitySharesOf(userAlice), 0);
    }

    // remainingMintingCapacitySharesOf tests

    function test_RemainingCapacity_EqualsTotal_WhenNoMinted() public view {
        uint256 totalCapacity = pool.totalMintingCapacitySharesOf(address(this));
        uint256 remainingCapacity = pool.remainingMintingCapacitySharesOf(address(this), 0);

        assertEq(remainingCapacity, totalCapacity);
    }

    function test_RemainingCapacity_DecreasesAfterMint() public {
        uint256 remainingBefore = pool.remainingMintingCapacitySharesOf(address(this), 0);
        uint256 wstethToMint = 1 * 10 ** 18;

        pool.mintWsteth(wstethToMint);

        uint256 remainingAfter = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertEq(remainingAfter, remainingBefore - wstethToMint);
    }

    function test_RemainingCapacity_ZeroAfterFullMint() public {
        uint256 fullCapacity = pool.remainingMintingCapacitySharesOf(address(this), 0);

        pool.mintWsteth(fullCapacity);

        assertEq(pool.remainingMintingCapacitySharesOf(address(this), 0), 0);
    }

    function test_RemainingCapacity_WithFutureDeposit_IncludesIt() public view {
        uint256 futureDeposit = 2 ether;

        uint256 capacityWithoutDeposit = pool.remainingMintingCapacitySharesOf(address(this), 0);
        uint256 capacityWithDeposit = pool.remainingMintingCapacitySharesOf(address(this), futureDeposit);

        assertGt(capacityWithDeposit, capacityWithoutDeposit);
    }

    function test_RemainingCapacity_AfterTransfer_Recalculated() public {
        uint256 transferAmount = pool.balanceOf(address(this)) / 2;
        uint256 aliceCapacityBefore = pool.remainingMintingCapacitySharesOf(userAlice, 0);

        assertTrue(pool.transfer(userAlice, transferAmount));

        uint256 aliceCapacityAfter = pool.remainingMintingCapacitySharesOf(userAlice, 0);
        assertGt(aliceCapacityAfter, aliceCapacityBefore);
    }

    // Fuzz test for remainingMintingCapacitySharesOf with different stv rate

    function testFuzz_RemainingCapacity_CalculatedValueCanBeMinted(uint96 _ethToDeposit, int64 _rewards) public {
        vm.assume(_rewards > -pool.totalAssets().toInt256().toInt64());
        vm.assume(_ethToDeposit > 0);

        // Rewards
        dashboard.mock_simulateRewards(int256(_rewards));

        // Deposit and mint
        uint256 remainingCapacity = pool.remainingMintingCapacitySharesOf(address(this), _ethToDeposit);
        vm.deal(address(this), _ethToDeposit);
        pool.depositETHAndMintStethShares{value: _ethToDeposit}(address(0), remainingCapacity);
    }
}
