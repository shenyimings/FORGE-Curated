// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {Test} from "forge-std/Test.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";

contract BurningWstethTest is Test, SetupStvStETHPool {
    uint256 ethToDeposit = 4 ether;
    uint256 wstethToMint = 1 * 10 ** 18; // 1 wstETH

    uint256 constant ALLOWED_ROUNDING_ERROR = 10; // Allowable error due to wrapping/unwrapping on wstETH contract

    function setUp() public override {
        super.setUp();
        // Deposit ETH and mint wstETH for testing burn functionality
        pool.depositETH{value: ethToDeposit}(address(this), address(0));
        pool.mintWsteth(wstethToMint);

        // Approve pool to spend wstETH for burning
        wsteth.approve(address(pool), type(uint256).max);
    }

    function _previewUnwrappedStethShares(uint256 _wsteth) internal view returns (uint256 stethShares) {
        // Calculate stETH shares corresponding to the given wstETH amount
        // Can differ due to implementation specifics of the wsteth.unwrap function
        stethShares = steth.getSharesByPooledEth(steth.getPooledEthByShares(_wsteth));
    }

    // Initial state tests

    function test_InitialState_HasMintedStethShares() public view {
        assertEq(pool.totalMintedStethShares(), wstethToMint);
        assertEq(pool.mintedStethSharesOf(address(this)), wstethToMint);
    }

    function test_InitialState_HasStethBalance() public view {
        assertEq(wsteth.balanceOf(address(this)), wstethToMint);
    }

    // burn wstETH tests

    function test_BurnWsteth_DecreasesTotalMintedShares() public {
        uint256 totalBefore = pool.totalMintedStethShares();
        uint256 wstethToBurn = wstethToMint / 2;
        uint256 expectedSharesToBurn = _previewUnwrappedStethShares(wstethToBurn);

        pool.burnWsteth(wstethToBurn);

        assertEq(pool.totalMintedStethShares(), totalBefore - expectedSharesToBurn);
    }

    function test_BurnWsteth_DecreasesUserMintedShares() public {
        uint256 userMintedBefore = pool.mintedStethSharesOf(address(this));
        uint256 wstethToBurn = wstethToMint / 2;
        uint256 expectedSharesToBurn = _previewUnwrappedStethShares(wstethToBurn);

        pool.burnWsteth(wstethToBurn);

        assertEq(pool.mintedStethSharesOf(address(this)), userMintedBefore - expectedSharesToBurn);
    }

    function test_BurnWsteth_EmitsEvent() public {
        uint256 wstethToBurn = wstethToMint / 2;
        uint256 expectedSharesToBurn = _previewUnwrappedStethShares(wstethToBurn);

        vm.expectEmit(true, false, false, true);
        emit StvStETHPool.StethSharesBurned(address(this), expectedSharesToBurn);

        pool.burnWsteth(wstethToBurn);
    }

    function test_BurnWsteth_CallsDashboardBurnShares() public {
        uint256 wstethToBurn = wstethToMint / 2;

        vm.expectCall(address(dashboard), abi.encodeWithSelector(dashboard.burnWstETH.selector, wstethToBurn));

        pool.burnWsteth(wstethToBurn);
    }

    function test_BurnWsteth_CallsStethTransferShares() public {
        uint256 wstethToBurn = wstethToMint / 2;
        uint256 expectedSharesToBurn = _previewUnwrappedStethShares(wstethToBurn);

        vm.expectCall(
            address(steth),
            abi.encodeWithSelector(steth.transferShares.selector, address(vaultHub), expectedSharesToBurn)
        );

        pool.burnWsteth(wstethToBurn);
    }

    function test_BurnWsteth_TransfersWstethFromUser() public {
        uint256 wstethToBurn = wstethToMint / 2;
        uint256 userBalanceBefore = wsteth.balanceOf(address(this));

        pool.burnWsteth(wstethToBurn);

        assertEq(wsteth.balanceOf(address(this)), userBalanceBefore - wstethToBurn);
    }

    function test_BurnWsteth_DoesNotLeaveWstethOnPool() public {
        uint256 wstethToBurn = wstethToMint / 2;

        pool.burnWsteth(wstethToBurn);

        assertEq(wsteth.balanceOf(address(pool)), 0);
    }

    function test_BurnWsteth_IncreasesAvailableCapacity() public {
        uint256 capacityBefore = pool.remainingMintingCapacitySharesOf(address(this), 0);
        uint256 wstethToBurn = wstethToMint / 2;
        uint256 expectedSharesToBurn = _previewUnwrappedStethShares(wstethToBurn);

        pool.burnWsteth(wstethToBurn);

        uint256 capacityAfter = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertEq(capacityAfter, capacityBefore + expectedSharesToBurn);
    }

    function test_BurnWsteth_PartialBurn() public {
        uint256 wstethToBurn = wstethToMint / 4;
        uint256 expectedSharesToBurn = _previewUnwrappedStethShares(wstethToBurn);

        pool.burnWsteth(wstethToBurn);

        assertEq(pool.mintedStethSharesOf(address(this)), wstethToMint - expectedSharesToBurn);
        assertEq(pool.totalMintedStethShares(), wstethToMint - expectedSharesToBurn);
    }

    function test_BurnWsteth_FullBurn() public {
        pool.burnWsteth(wstethToMint);

        // Burning can require a few more wei of wstETH due to the dust caused by wrapping/unwrapping in WSTETH contract
        assertApproxEqAbs(pool.mintedStethSharesOf(address(this)), 0, ALLOWED_ROUNDING_ERROR);
        assertApproxEqAbs(pool.totalMintedStethShares(), 0, ALLOWED_ROUNDING_ERROR);
    }

    function test_BurnWsteth_MultipleBurns() public {
        uint256 firstBurn = wstethToMint / 3;
        uint256 secondBurn = wstethToMint / 3;

        pool.burnWsteth(firstBurn);
        pool.burnWsteth(secondBurn);

        assertEq(
            pool.mintedStethSharesOf(address(this)),
            wstethToMint - _previewUnwrappedStethShares(firstBurn) - _previewUnwrappedStethShares(secondBurn)
        );
        assertEq(
            pool.totalMintedStethShares(),
            wstethToMint - _previewUnwrappedStethShares(firstBurn) - _previewUnwrappedStethShares(secondBurn)
        );
    }

    // Error cases

    function test_BurnWsteth_RevertOnZeroAmount() public {
        vm.expectRevert(StvStETHPool.ZeroArgument.selector);
        pool.burnWsteth(0);
    }

    function test_BurnWsteth_RevertOnInsufficientMintedShares() public {
        uint256 excessiveAmount = wstethToMint + 10; // More than 1 because of rounding errors

        vm.expectRevert(StvStETHPool.InsufficientMintedShares.selector);
        pool.burnWsteth(excessiveAmount);
    }

    function test_BurnWsteth_RevertOnInsufficientWstethBalance() public {
        // Transfer away wstETH so user doesn't have enough
        assertTrue(wsteth.transfer(userAlice, wsteth.balanceOf(address(this))));

        vm.expectRevert(); // Should revert on transfer
        pool.burnWsteth(wstethToMint);
    }

    function test_BurnWsteth_RevertAfterFullBurn() public {
        // First burn all shares
        pool.burnWsteth(wstethToMint);

        // Then try to burn more
        vm.expectRevert(StvStETHPool.InsufficientMintedShares.selector);
        pool.burnWsteth(10); // More than 1 because of rounding errors
    }

    // Different users tests

    function test_BurnWsteth_DifferentUsers() public {
        // Setup other users with deposits and mints
        vm.startPrank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));
        pool.mintWsteth(wstethToMint);
        wsteth.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(userBob);
        pool.depositETH{value: ethToDeposit}(userBob, address(0));
        pool.mintWsteth(wstethToMint);
        wsteth.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        uint256 totalBefore = pool.totalMintedStethShares();
        uint256 wstethToBurn = wstethToMint / 2;
        uint256 expectedSharesToBurn = _previewUnwrappedStethShares(wstethToBurn);

        // Alice burns
        vm.prank(userAlice);
        pool.burnWsteth(wstethToBurn);

        // Bob burns
        vm.prank(userBob);
        pool.burnWsteth(wstethToBurn);

        assertEq(pool.mintedStethSharesOf(userAlice), wstethToMint - expectedSharesToBurn);
        assertEq(pool.mintedStethSharesOf(userBob), wstethToMint - expectedSharesToBurn);
        assertEq(pool.totalMintedStethShares(), totalBefore - (expectedSharesToBurn * 2));
    }

    function test_BurnWsteth_DoesNotAffectOtherUsers() public {
        // Setup Alice with minted shares
        vm.startPrank(userAlice);
        pool.depositETH{value: ethToDeposit}(userAlice, address(0));
        pool.mintWsteth(wstethToMint);
        wsteth.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        uint256 aliceMintedBefore = pool.mintedStethSharesOf(userAlice);
        uint256 wstethToBurn = wstethToMint / 2;

        // This contract burns, should not affect Alice
        pool.burnWsteth(wstethToBurn);

        assertEq(pool.mintedStethSharesOf(userAlice), aliceMintedBefore);
    }

    // Capacity restoration tests

    function test_BurnWsteth_RestoresFullCapacity() public {
        // Use up all capacity
        uint256 additionalMint = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintWsteth(additionalMint);

        // Burn all shares
        uint256 totalMinted = pool.mintedStethSharesOf(address(this));
        pool.burnWsteth(totalMinted);

        // Capacity should be fully restored (allow some leeway for rounding errors)
        uint256 capacityAfterBurn = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertApproxEqAbs(capacityAfterBurn, totalMinted, ALLOWED_ROUNDING_ERROR);
    }

    function test_BurnWsteth_PartialCapacityRestore() public {
        uint256 additionalMint = pool.remainingMintingCapacitySharesOf(address(this), 0);
        pool.mintWsteth(additionalMint);

        uint256 capacityBefore = pool.remainingMintingCapacitySharesOf(address(this), 0);
        uint256 wstethToBurn = additionalMint / 2;
        uint256 expectedSharesToBurn = _previewUnwrappedStethShares(wstethToBurn);

        pool.burnWsteth(wstethToBurn);

        uint256 capacityAfter = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertEq(capacityAfter, capacityBefore + expectedSharesToBurn);
    }

    // Edge cases

    function test_BurnWsteth_1Wei_ShareRateEq1() public {
        steth.mock_setTotalPooled(100 * 10 ** 18, 100 * 10 ** 18); // share rate = 1

        uint256 minimalBurn = 1; // 1 wei
        uint256 mintedBefore = pool.mintedStethSharesOf(address(this));

        pool.burnWsteth(minimalBurn);

        assertEq(pool.mintedStethSharesOf(address(this)), mintedBefore - minimalBurn);
    }

    function test_BurnWsteth_1Wei_ShareRateGt1() public {
        steth.mock_setTotalPooled(101 * 10 ** 18, 100 * 10 ** 18); // share rate > 1

        vm.expectRevert(StvStETHPool.ZeroArgument.selector); // _getPooledEthByShares(1) == 1 -> _getSharesByPooledEth(1) == 0
        pool.burnWsteth(1);
    }

    function test_BurnWsteth_1Wei_ShareRateLt1() public {
        steth.mock_setTotalPooled(50 * 10 ** 18, 100 * 10 ** 18); // share rate = 0.5

        vm.expectRevert(StvStETHPool.ZeroArgument.selector); // _getPooledEthByShares(1) == 0
        pool.burnWsteth(1);
    }

    function test_BurnWsteth_AfterRewards() public {
        // Simulate rewards accrual
        dashboard.mock_simulateRewards(int256(1 ether));

        uint256 wstethToBurn = wstethToMint / 2;
        uint256 capacityBefore = pool.remainingMintingCapacitySharesOf(address(this), 0);
        uint256 expectedSharesToBurn = _previewUnwrappedStethShares(wstethToBurn);

        pool.burnWsteth(wstethToBurn);

        uint256 capacityAfter = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertGe(capacityAfter, capacityBefore + expectedSharesToBurn); // Should be at least as high due to rewards
    }

    function test_BurnWsteth_ExactBurnOfAllShares() public {
        uint256 allMintedShares = pool.mintedStethSharesOf(address(this));

        pool.burnWsteth(allMintedShares);

        // Burning can require a few more wei of wstETH due to the dust caused by wrapping/unwrapping in WSTETH contract
        assertApproxEqAbs(pool.mintedStethSharesOf(address(this)), 0, ALLOWED_ROUNDING_ERROR);
        assertApproxEqAbs(pool.totalMintedStethShares(), 0, ALLOWED_ROUNDING_ERROR);
    }

    // Approvals

    function test_BurnWsteth_RequiresApproval() public {
        // Test that burning requires proper stETH approval
        uint256 wstethToBurn = wstethToMint / 2;

        // Reset approval (assuming it was set during setup)
        wsteth.approve(address(pool), 0);

        // Should fail without approval
        vm.expectRevert();
        pool.burnWsteth(wstethToBurn);

        // Should succeed with approval (need to approve stETH amount, not shares)
        uint256 stethAmount = steth.getPooledEthByShares(wstethToBurn);
        uint256 expectedSharesToBurn = _previewUnwrappedStethShares(wstethToBurn);
        wsteth.approve(address(pool), stethAmount);
        pool.burnWsteth(wstethToBurn);

        assertEq(pool.mintedStethSharesOf(address(this)), wstethToMint - expectedSharesToBurn);
    }

    // Rounding tests

    function test_BurnWsteth_AccountsForRoundingLoss() public {
        // Set share rate to create rounding loss
        steth.mock_setTotalPooled(1001 * 10 ** 18, 1000 * 10 ** 18); // share rate = 1.001

        uint256 wstethToBurn = 123456789; // Odd number to trigger rounding
        uint256 mintedBefore = pool.mintedStethSharesOf(address(this));
        uint256 totalLiabilityBefore = pool.totalLiabilityShares();

        // Calculate what actually gets burned (simulating unwrap rounding)
        uint256 unwrappedSteth = steth.getPooledEthByShares(wstethToBurn);
        uint256 unwrappedStethShares = steth.getSharesByPooledEth(unwrappedSteth);

        // Verify rounding occurred
        assertGt(wstethToBurn, unwrappedStethShares);
        assertEq(wstethToBurn - unwrappedStethShares, 1); // 1 share lost due to rounding

        pool.burnWsteth(wstethToBurn);

        // User's liability should decrease by unwrapped shares, accounting for rounding loss
        assertEq(pool.mintedStethSharesOf(address(this)), mintedBefore - unwrappedStethShares);
        assertLt(unwrappedStethShares, wstethToBurn); // Loss due to rounding

        // Total liability should decrease by unwrapped shares, accounting for rounding loss
        uint256 totalLiabilityDecrease = totalLiabilityBefore - pool.totalLiabilityShares();
        assertEq(totalLiabilityDecrease, unwrappedStethShares);
        assertLt(totalLiabilityDecrease, wstethToBurn); // Loss due to rounding
    }

    function test_BurnWsteth_DustAccumulatesOnWsteth() public {
        // Set share rate to create dust
        steth.mock_setTotalPooled(1001 * 10 ** 18, 1000 * 10 ** 18); // share rate = 1.001

        uint256 wstethToBurn = 123456789;

        // Unwrap simulation: wsteth -> steth -> shares
        uint256 unwrappedSteth = steth.getPooledEthByShares(wstethToBurn);
        uint256 unwrappedStethShares = steth.getSharesByPooledEth(unwrappedSteth);

        // Verify rounding occurred
        assertGt(wstethToBurn, unwrappedStethShares);
        assertEq(wstethToBurn - unwrappedStethShares, 1); // 1 share lost due to rounding

        // Record stETH shares on WSTETH contract before burn
        uint256 stethSharesOnWstethBefore = steth.sharesOf(address(wsteth));

        pool.burnWsteth(wstethToBurn);

        // Verify some dust remains on wstETH contract 
        uint256 stethSharesOnWstethDecrease = stethSharesOnWstethBefore - steth.sharesOf(address(wsteth));
        assertEq(stethSharesOnWstethDecrease, unwrappedStethShares); // Shares decreased by unwrapped amount
        assertGt(wstethToBurn, stethSharesOnWstethDecrease); // Loss due to rounding
        assertEq(wstethToBurn - stethSharesOnWstethDecrease, 1); // 1 share of dust remains
    }
}
