// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Upgrades } from "../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IMTokenLike } from "../../src/interfaces/IMTokenLike.sol";

import { MYieldToOne } from "../../src/projects/yieldToOne/MYieldToOne.sol";

import { BaseIntegrationTest } from "../utils/BaseIntegrationTest.sol";

contract MYieldToOneIntegrationTests is BaseIntegrationTest {
    uint256 public mainnetFork;

    function setUp() public override {
        mainnetFork = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 22_482_175);

        super.setUp();

        _fundAccounts();

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
    }

    function test_integration_constants() external view {
        // Check the contract's name, symbol, and decimals
        assertEq(mYieldToOne.name(), NAME);
        assertEq(mYieldToOne.symbol(), SYMBOL);
        assertEq(mYieldToOne.decimals(), 6);

        // Check the initial state of the contract
        assertEq(mYieldToOne.mToken(), address(mToken));
        assertEq(mYieldToOne.yieldRecipient(), yieldRecipient);
    }

    function test_yieldAccumulationAndClaim() external {
        uint256 amount = 10e6;

        // Enable earning for the contract
        _addToList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.enableEarning();

        // Check the initial earning state
        assertEq(mToken.isEarning(address(mYieldToOne)), true);

        vm.warp(vm.getBlockTimestamp() + 1 days);

        // wrap from non-earner account
        _swapInM(address(mYieldToOne), alice, alice, amount);

        // Check balances of MYieldToOne and Alice after wrapping
        assertEq(mYieldToOne.balanceOf(alice), amount); // user receives exact amount
        assertApproxEqAbs(mToken.balanceOf(address(mYieldToOne)), amount, 2); // rounds down

        // Fast forward 10 days in the future to generate yield
        vm.warp(vm.getBlockTimestamp() + 10 days);

        // yield accrual
        assertEq(mYieldToOne.yield(), 11375);

        // transfers do not affect yield
        vm.prank(alice);
        mYieldToOne.transfer(bob, amount / 2);

        assertEq(mYieldToOne.balanceOf(bob), amount / 2);
        assertEq(mYieldToOne.balanceOf(alice), amount / 2);

        // yield stays the same
        assertEq(mYieldToOne.yield(), 11375);

        // unwraps
        _swapMOut(address(mYieldToOne), alice, alice, amount / 2);

        // alice receives exact amount but mYieldToOne loses 1 wei
        // due to rounding up in M when transferring from an earner to a non-earner
        assertEq(mYieldToOne.yield(), 11374);

        _swapMOut(address(mYieldToOne), bob, bob, amount / 2);

        assertEq(mYieldToOne.yield(), 11373);

        assertEq(mYieldToOne.balanceOf(bob), 0);
        assertEq(mYieldToOne.balanceOf(alice), 0);
        assertEq(mToken.balanceOf(bob), amount + amount / 2);
        assertEq(mToken.balanceOf(alice), amount / 2);

        assertEq(mYieldToOne.balanceOf(yieldRecipient), 0);

        // claim yield
        mYieldToOne.claimYield();

        assertEq(mYieldToOne.balanceOf(yieldRecipient), 11373);
        assertEq(mYieldToOne.yield(), 0);
        assertEq(mToken.balanceOf(address(mYieldToOne)), 11373);
        assertEq(mYieldToOne.totalSupply(), 11373);

        // wrap from earner account
        _addToList(EARNERS_LIST, bob);

        vm.prank(bob);
        mToken.startEarning();

        _swapInM(address(mYieldToOne), bob, bob, amount);

        // Check balances of MYieldToOne and Bob after wrapping
        assertEq(mYieldToOne.balanceOf(bob), amount);
        assertEq(mToken.balanceOf(address(mYieldToOne)), 11373 + amount);

        // Disable earning for the contract
        _removeFomList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.disableEarning();

        assertFalse(mYieldToOne.isEarningEnabled());

        // Fast forward 10 days in the future
        vm.warp(vm.getBlockTimestamp() + 10 days);

        // No yield should accrue
        assertEq(mYieldToOne.yield(), 0);

        // Re-enable earning for the contract
        _addToList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.enableEarning();

        // Yield should accrue again
        vm.warp(vm.getBlockTimestamp() + 10 days);

        assertEq(mYieldToOne.yield(), 11388);
    }

    /* ============ enableEarning ============ */

    function test_enableEarning_notApprovedEarner() external {
        vm.expectRevert(abi.encodeWithSelector(IMTokenLike.NotApprovedEarner.selector));
        mYieldToOne.enableEarning();
    }

    /* ============ disableEarning ============ */

    function test_disableEarning_approvedEarner() external {
        _addToList(EARNERS_LIST, address(mYieldToOne));
        mYieldToOne.enableEarning();

        vm.expectRevert(abi.encodeWithSelector(IMTokenLike.IsApprovedEarner.selector));
        mYieldToOne.disableEarning();
    }

    /* ============ swap in M with permit ============ */

    function test_wrapWithPermits() external {
        _addToList(EARNERS_LIST, address(mYieldToOne));

        assertEq(mToken.balanceOf(alice), 10e6);

        _swapInMWithPermitVRS(address(mYieldToOne), alice, aliceKey, alice, 5e6, 0, block.timestamp);

        assertEq(mYieldToOne.balanceOf(alice), 5e6);
        assertEq(mToken.balanceOf(alice), 5e6);

        _swapInMWithPermitVRS(address(mYieldToOne), alice, aliceKey, alice, 5e6, 1, block.timestamp);

        assertEq(mYieldToOne.balanceOf(alice), 10e6);
        assertEq(mToken.balanceOf(alice), 0);
    }
}
