// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Upgrades, UnsafeUpgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { MEarnerManager } from "../../src/projects/earnerManager/MEarnerManager.sol";

import { BaseIntegrationTest } from "../utils/BaseIntegrationTest.sol";

contract MEarnerManagerIntegrationTests is BaseIntegrationTest {
    uint256 public mainnetFork;

    function setUp() public override {
        mainnetFork = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 22_482_175);

        super.setUp();

        _fundAccounts();

        mEarnerManager = MEarnerManager(
            Upgrades.deployUUPSProxy(
                "MEarnerManager.sol:MEarnerManager",
                abi.encodeWithSelector(
                    MEarnerManager.initialize.selector,
                    NAME,
                    SYMBOL,
                    address(mToken),
                    address(swapFacility),
                    admin,
                    earnerManager,
                    feeRecipient
                )
            )
        );
    }

    function test_integration_constants() external view {
        assertEq(mEarnerManager.name(), NAME);
        assertEq(mEarnerManager.symbol(), SYMBOL);
        assertEq(mEarnerManager.decimals(), 6);
        assertEq(mEarnerManager.mToken(), address(mToken));
        assertEq(mEarnerManager.feeRecipient(), feeRecipient);
        assertEq(mEarnerManager.ONE_HUNDRED_PERCENT(), 10_000);
        assertTrue(mEarnerManager.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mEarnerManager.hasRole(EARNER_MANAGER_ROLE, earnerManager));
    }

    function test_yieldAccumulationAndClaim() external {
        // Enable earning for the contract
        _addToList(EARNERS_LIST, address(mEarnerManager));
        mEarnerManager.enableEarning();

        // Check the initial earning state
        assertEq(mToken.isEarning(address(mEarnerManager)), true);
        assertEq(mEarnerManager.isEarningEnabled(), true);

        // Add earners with different fee rates
        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 10_000); // 100% fee

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(bob, true, 5_000); // 50% fee

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(carol, true, 0); // 0% fee

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(david, true, 0);

        uint256 amount = 10e6;

        // Wraps
        vm.prank(alice);
        mToken.approve(address(swapFacility), amount);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), amount, alice);

        vm.prank(bob);
        mToken.approve(address(swapFacility), amount);

        vm.prank(bob);
        swapFacility.swapInM(address(mEarnerManager), amount, bob);

        vm.prank(carol);
        mToken.approve(address(swapFacility), amount);

        vm.prank(carol);
        swapFacility.swapInM(address(mEarnerManager), amount, carol);

        // Check balances of MEarnerManager and users after wrapping
        assertEq(mEarnerManager.balanceOf(alice), amount);
        assertEq(mEarnerManager.balanceOf(bob), amount);
        assertEq(mEarnerManager.balanceOf(carol), amount);
        assertEq(mEarnerManager.totalSupply(), amount * 3); // 3 users wrapped

        assertEq(mToken.balanceOf(alice), 0);
        assertEq(mToken.balanceOf(bob), 0);
        assertEq(mToken.balanceOf(carol), 0);

        assertApproxEqAbs(mToken.balanceOf(address(mEarnerManager)), amount * 3, 6); // 3 users wrapped
        assertEq(mEarnerManager.currentIndex(), mToken.currentIndex());

        vm.warp(vm.getBlockTimestamp() + 1 days);

        (uint256 aliceYieldWithFee, uint256 aliceFee, uint256 aliceYield) = mEarnerManager.accruedYieldAndFeeOf(alice);
        (uint256 bobYieldWithFee, uint256 bobFee, uint256 bobYield) = mEarnerManager.accruedYieldAndFeeOf(bob);
        (uint256 carolYieldWithFee, uint256 carolFee, uint256 carolYield) = mEarnerManager.accruedYieldAndFeeOf(carol);

        // Total accrued yield for all users should be the same
        assertEq(aliceYieldWithFee, bobYieldWithFee);
        assertEq(aliceYieldWithFee, carolYieldWithFee);

        assertEq(aliceFee, aliceYieldWithFee); // 100% fee for Alice
        assertEq(bobFee, bobYieldWithFee / 2); // 50% fee for Bob
        assertEq(carolFee, 0); // 0% fee for Carol

        assertEq(aliceYieldWithFee, aliceFee + aliceYield);
        assertEq(bobYieldWithFee, bobFee + bobYield);
        assertEq(carolYieldWithFee, carolFee + carolYield);

        vm.prank(alice);
        mEarnerManager.transfer(david, amount / 2);

        (uint256 aliceYieldWithFee1, , ) = mEarnerManager.accruedYieldAndFeeOf(alice);

        assertApproxEqAbs(aliceYieldWithFee1, aliceYieldWithFee, 2); // Unclaimed yield does not change after transfer

        (aliceYieldWithFee, aliceFee, ) = mEarnerManager.claimFor(alice);
        (bobYieldWithFee, bobFee, ) = mEarnerManager.claimFor(bob);
        (carolYieldWithFee, carolFee, ) = mEarnerManager.claimFor(carol);

        assertEq(mEarnerManager.balanceOf(feeRecipient), aliceFee + bobFee + carolFee);

        // After claiming accrued yield is 0
        assertEq(mEarnerManager.accruedYieldOf(alice), 0);
        assertEq(mEarnerManager.accruedYieldOf(bob), 0);
        assertEq(mEarnerManager.accruedYieldOf(carol), 0);

        vm.warp(vm.getBlockTimestamp() + 10 days);

        uint256 feeRecipientYield = mEarnerManager.accruedYieldOf(feeRecipient);

        mEarnerManager.claimFor(feeRecipient);

        assertEq(mEarnerManager.balanceOf(feeRecipient), aliceFee + bobFee + carolFee + feeRecipientYield);
    }

    function test_fieldRecipient() external {
        // Enable earning for the contract
        _addToList(EARNERS_LIST, address(mEarnerManager));
        mEarnerManager.enableEarning();

        // Add earners with different fee rates
        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 1_000); // 10% fee

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(bob, true, 1_000); // 10% fee

        uint256 amount = 10e6;

        // Mint tokens for Alice
        vm.prank(alice);
        mToken.approve(address(swapFacility), amount);
        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), amount, alice);

        // Mint tokens for Bob
        vm.prank(bob);
        mToken.approve(address(swapFacility), amount);
        vm.prank(bob);
        swapFacility.swapInM(address(mEarnerManager), amount, bob);

        vm.warp(vm.getBlockTimestamp() + 365 days);

        assertEq(mEarnerManager.balanceOf(feeRecipient), 0);

        (uint256 bobYield, uint256 bobFee, uint256 bobYieldNetOfFees) = mEarnerManager.accruedYieldAndFeeOf(bob);

        vm.prank(earnerManager);
        mEarnerManager.setFeeRecipient(bob);

        assertEq(mEarnerManager.balanceOf(feeRecipient), bobFee);
        assertEq(mEarnerManager.balanceOf(bob), amount + bobYieldNetOfFees);

        (uint256 aliceYield, uint256 aliceFee, uint256 aliceYieldNetOfFees) = mEarnerManager.claimFor(alice);

        assertEq(aliceFee, (10 * aliceYield) / 100); // 10% fee for Alice

        assertEq(mEarnerManager.balanceOf(bob), amount + bobYieldNetOfFees + aliceFee);
        assertEq(mEarnerManager.balanceOf(feeRecipient), bobFee);
        assertEq(mEarnerManager.balanceOf(alice), amount + aliceYieldNetOfFees);

        (bobYield, bobFee, bobYieldNetOfFees) = mEarnerManager.claimFor(bob);

        // Bob unclaimed yield is 0 after `mEarnerManager.setFeeRecipient(bob)` call
        assertEq(bobYield, 0);
        assertEq(bobFee, 0);
        assertEq(bobYieldNetOfFees, 0);
    }
}
