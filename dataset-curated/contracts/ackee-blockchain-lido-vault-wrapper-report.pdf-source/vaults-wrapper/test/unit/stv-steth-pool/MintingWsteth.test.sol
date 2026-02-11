// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {Test} from "forge-std/Test.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";

contract MintingWstethTest is Test, SetupStvStETHPool {
    uint256 ethToDeposit = 4 ether;
    uint256 wstethToMint = 1 * 10 ** 18; // 1 wstETH

    function setUp() public override {
        super.setUp();
        // Deposit some ETH to get minting capacity
        pool.depositETH{value: ethToDeposit}(address(this), address(0));
    }

    // Initial state tests

    function test_InitialState_NoMintedWsteth() public view {
        assertEq(wsteth.balanceOf(address(this)), 0);
    }

    // Mint wstETH tests

    function test_MintWsteth_IncreasesTotalMintedShares() public {
        uint256 totalBefore = pool.totalMintedStethShares();

        pool.mintWsteth(wstethToMint);

        assertEq(pool.totalMintedStethShares(), totalBefore + wstethToMint);
    }

    function test_MintWsteth_IncreasesUserStethBalance() public {
        uint256 userWstethBefore = wsteth.balanceOf(address(this));
        pool.mintWsteth(wstethToMint);
        uint256 userWstethAfter = wsteth.balanceOf(address(this));

        assertEq(userWstethAfter, userWstethBefore + wstethToMint);
    }

    function test_MintWsteth_IncreasesUserMintedShares() public {
        uint256 userMintedBefore = pool.mintedStethSharesOf(address(this));

        pool.mintWsteth(wstethToMint);

        assertEq(pool.mintedStethSharesOf(address(this)), userMintedBefore + wstethToMint);
    }

    function test_MintWsteth_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit StvStETHPool.StethSharesMinted(address(this), wstethToMint);

        pool.mintWsteth(wstethToMint);
    }

    function test_MintWsteth_CallsDashboardMintShares() public {
        // Check that dashboard's mint function is called with correct parameters
        vm.expectCall(
            address(dashboard), abi.encodeWithSelector(dashboard.mintWstETH.selector, address(this), wstethToMint)
        );

        pool.mintWsteth(wstethToMint);
    }

    function test_MintWsteth_DecreasesAvailableCapacity() public {
        uint256 capacityBefore = pool.remainingMintingCapacitySharesOf(address(this), 0);

        pool.mintWsteth(wstethToMint);

        uint256 capacityAfter = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertEq(capacityAfter, capacityBefore - wstethToMint);
    }

    function test_MintWsteth_MultipleMints() public {
        uint256 firstMint = wstethToMint / 2;
        uint256 secondMint = wstethToMint / 2;

        pool.mintWsteth(firstMint);
        pool.mintWsteth(secondMint);

        assertEq(pool.mintedStethSharesOf(address(this)), firstMint + secondMint);
        assertEq(pool.totalMintedStethShares(), firstMint + secondMint);
    }

    // Error cases

    function test_MintWsteth_RevertOnZeroAmount() public {
        vm.expectRevert(StvStETHPool.ZeroArgument.selector);
        pool.mintWsteth(0);
    }

    function test_MintWsteth_RevertOnInsufficientCapacity() public {
        uint256 capacity = pool.remainingMintingCapacitySharesOf(address(this), 0);
        uint256 excessiveAmount = capacity + 1;

        vm.expectRevert(StvStETHPool.InsufficientMintingCapacity.selector);
        pool.mintWsteth(excessiveAmount);
    }

    function test_MintWsteth_RevertOnExactlyExceedingCapacity() public {
        uint256 capacity = pool.remainingMintingCapacitySharesOf(address(this), 0);

        // First mint should succeed
        pool.mintWsteth(capacity);

        // Second mint should fail even with 1 wei
        vm.expectRevert(StvStETHPool.InsufficientMintingCapacity.selector);
        pool.mintWsteth(1);
    }

    // Different users tests

    function test_MintWsteth_DifferentUsers() public {
        vm.prank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));

        vm.prank(userBob);
        pool.depositETH{value: ethToDeposit}(userBob, address(0));

        // Both users should have minting capacity
        uint256 aliceCapacity = pool.remainingMintingCapacitySharesOf(userAlice, 0);
        uint256 bobCapacity = pool.remainingMintingCapacitySharesOf(userBob, 0);

        assertGt(aliceCapacity, 0);
        assertGt(bobCapacity, 0);

        // Both should be able to mint
        vm.prank(userAlice);
        pool.mintWsteth(wstethToMint);

        vm.prank(userBob);
        pool.mintWsteth(wstethToMint);

        assertEq(pool.mintedStethSharesOf(userAlice), wstethToMint);
        assertEq(pool.mintedStethSharesOf(userBob), wstethToMint);
        assertEq(pool.totalMintedStethShares(), wstethToMint * 2);
    }
}
