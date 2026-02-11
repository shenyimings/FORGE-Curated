// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Upgrades, UnsafeUpgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IMTokenLike } from "../../src/interfaces/IMTokenLike.sol";

import { MYieldFee } from "../../src/projects/yieldToAllWithFee/MYieldFee.sol";

import { BaseIntegrationTest } from "../utils/BaseIntegrationTest.sol";

contract MYieldFeeIntegrationTests is BaseIntegrationTest {
    uint256 public mainnetFork;

    function setUp() public override {
        mainnetFork = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 22_482_175);

        super.setUp();

        _fundAccounts();

        mYieldFee = MYieldFee(
            Upgrades.deployUUPSProxy(
                "MYieldFee.sol:MYieldFee",
                abi.encodeWithSelector(
                    MYieldFee.initialize.selector,
                    NAME,
                    SYMBOL,
                    address(mToken),
                    address(swapFacility),
                    YIELD_FEE_RATE,
                    feeRecipient,
                    admin,
                    yieldFeeManager,
                    claimRecipientManager
                )
            )
        );
    }

    function test_integration_constants() external view {
        assertEq(mYieldFee.name(), NAME);
        assertEq(mYieldFee.symbol(), SYMBOL);
        assertEq(mYieldFee.decimals(), 6);
        assertEq(mYieldFee.mToken(), address(mToken));
        assertEq(mYieldFee.ONE_HUNDRED_PERCENT(), 10_000);
        assertEq(mYieldFee.latestIndex(), EXP_SCALED_ONE);
        assertEq(mYieldFee.feeRate(), YIELD_FEE_RATE);
        assertEq(mYieldFee.feeRecipient(), feeRecipient);
        assertTrue(mYieldFee.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mYieldFee.hasRole(FEE_MANAGER_ROLE, yieldFeeManager));
    }

    function test_yieldAccumulationAndClaim() external {
        uint256 amount = 10e6;

        // Enable earning for the contract
        _addToList(EARNERS_LIST, address(mYieldFee));
        mYieldFee.enableEarning();

        // Check the initial earning state and index
        assertEq(mToken.isEarning(address(mYieldFee)), true);
        assertEq(mYieldFee.currentIndex(), EXP_SCALED_ONE);

        vm.warp(vm.getBlockTimestamp() + 1 days);

        // swap M to extension from non-earner account
        _swapInM(address(mYieldFee), alice, alice, amount);

        // Check balances of MYieldFee and Alice after wrapping
        assertEq(mYieldFee.balanceOf(alice), amount); // user receives exact amount
        assertApproxEqAbs(mToken.balanceOf(address(mYieldFee)), amount, 2); // rounds down

        // Fast forward 10 days in the future to generate yield
        vm.warp(vm.getBlockTimestamp() + 10 days);

        // yield accrual
        uint256 totalYield = 11375;
        uint256 yieldFee = _getYieldFee(totalYield, YIELD_FEE_RATE);

        assertApproxEqAbs(mYieldFee.totalAccruedYield(), totalYield - yieldFee, 1); // May round down
        assertEq(mYieldFee.totalAccruedFee(), yieldFee);

        // transfers do not affect yield (except for rounding error)
        vm.prank(alice);
        mYieldFee.transfer(bob, amount / 2);

        assertEq(mYieldFee.balanceOf(bob), amount / 2);
        assertEq(mYieldFee.balanceOf(alice), amount / 2);

        // yield accrual
        assertApproxEqAbs(mYieldFee.totalAccruedYield(), totalYield - yieldFee, 1); // May round down
        assertEq(mYieldFee.totalAccruedFee(), yieldFee);

        // unwraps
        _swapMOut(address(mYieldFee), alice, alice, amount / 2);

        // yield stays basically the same (except rounding up error on transfer)
        assertApproxEqAbs(mYieldFee.totalAccruedYield(), totalYield - yieldFee, 1); // May round down
        assertApproxEqAbs(mYieldFee.totalAccruedFee(), yieldFee, 1); // May round down

        _swapMOut(address(mYieldFee), bob, bob, amount / 2);

        // yield stays basically the same (except rounding up error on transfer)
        assertApproxEqAbs(mYieldFee.totalAccruedYield(), totalYield - yieldFee, 1); // May round down
        assertApproxEqAbs(mYieldFee.totalAccruedFee(), yieldFee, 2); // May round down

        assertEq(mYieldFee.balanceOf(bob), 0);
        assertEq(mYieldFee.balanceOf(alice), 0);
        assertEq(mToken.balanceOf(bob), amount + amount / 2);
        assertEq(mToken.balanceOf(alice), amount / 2);

        assertEq(mToken.balanceOf(feeRecipient), 0);

        // claim yield
        uint256 aliceYield = mYieldFee.claimYieldFor(alice);
        yieldFee = mYieldFee.claimFee();
        mYieldFee.claimYieldFor(bob);

        assertEq(mYieldFee.balanceOf(alice), aliceYield);
        assertEq(mYieldFee.balanceOf(bob), 0); // Bob's yield is 0 cause he received and unwrapped in the same block

        assertEq(mYieldFee.balanceOf(feeRecipient), yieldFee);
        assertApproxEqAbs(mToken.balanceOf(address(mYieldFee)), aliceYield + yieldFee, 1); // May round up
        assertEq(mYieldFee.totalSupply(), aliceYield + yieldFee);
        assertEq(mYieldFee.totalAccruedYield(), 0);
        assertEq(mYieldFee.totalAccruedFee(), 0);

        // Alice and yield fee recipient unwraps
        _swapMOut(address(mYieldFee), alice, alice, aliceYield);
        _swapMOut(address(mYieldFee), feeRecipient, feeRecipient, yieldFee);

        assertEq(mYieldFee.accruedYieldOf(alice), 0);
        assertEq(mYieldFee.balanceOf(alice), 0);
        assertEq(mToken.balanceOf(alice), amount / 2 + aliceYield);

        assertEq(mYieldFee.accruedYieldOf(feeRecipient), 0);
        assertEq(mYieldFee.balanceOf(feeRecipient), 0);
        assertEq(mToken.balanceOf(feeRecipient), yieldFee);
        assertEq(mToken.balanceOf(address(mYieldFee)), 0);

        // wrap from earner account
        _addToList(EARNERS_LIST, bob);

        vm.prank(bob);
        mToken.startEarning();

        _swapInM(address(mYieldFee), bob, bob, amount);

        // Check balances of MYieldFee and Bob after wrapping
        assertEq(mYieldFee.balanceOf(bob), amount);
        assertApproxEqAbs(mToken.balanceOf(address(mYieldFee)), amount, 1);

        // Disable earning for the contract
        _removeFomList(EARNERS_LIST, address(mYieldFee));
        mYieldFee.disableEarning();

        assertFalse(mYieldFee.isEarningEnabled());

        // Fast forward 10 days in the future
        vm.warp(vm.getBlockTimestamp() + 10 days);

        // No yield should accrue
        assertEq(mYieldFee.totalAccruedYield(), 0);

        // Re-enable earning for the contract
        _addToList(EARNERS_LIST, address(mYieldFee));
        mYieldFee.enableEarning();

        // Yield should accrue again
        vm.warp(vm.getBlockTimestamp() + 10 days);

        assertApproxEqAbs(mYieldFee.totalAccruedYield(), totalYield - yieldFee, 3); // May round down
        assertApproxEqAbs(mToken.balanceOf(address(mYieldFee)), amount + totalYield, 1);
    }

    /* ============ enableEarning ============ */

    function test_enableEarning_notApprovedEarner() external {
        vm.expectRevert(abi.encodeWithSelector(IMTokenLike.NotApprovedEarner.selector));
        mYieldFee.enableEarning();
    }

    /* ============ disableEarning ============ */

    function test_disableEarning_approvedEarner() external {
        _addToList(EARNERS_LIST, address(mYieldFee));
        mYieldFee.enableEarning();

        vm.expectRevert(abi.encodeWithSelector(IMTokenLike.IsApprovedEarner.selector));
        mYieldFee.disableEarning();
    }

    /* ============ swap in M with permit ============ */

    function test_wrapWithPermits() external {
        _addToList(EARNERS_LIST, address(mYieldFee));

        assertEq(mToken.balanceOf(alice), 10e6);

        _swapInMWithPermitVRS(address(mYieldFee), alice, aliceKey, alice, 5e6, 0, block.timestamp);

        assertEq(mYieldFee.balanceOf(alice), 5e6);
        assertEq(mToken.balanceOf(alice), 5e6);

        _swapInMWithPermitVRS(address(mYieldFee), alice, aliceKey, alice, 5e6, 1, block.timestamp);

        assertEq(mYieldFee.balanceOf(alice), 10e6);
        assertEq(mToken.balanceOf(alice), 0);
    }
}
