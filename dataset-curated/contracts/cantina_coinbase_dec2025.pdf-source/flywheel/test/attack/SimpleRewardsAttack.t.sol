// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";

import {MockERC20} from "../lib/mocks/MockERC20.sol";

import {Flywheel} from "../../src/Flywheel.sol";
import {SimpleRewards} from "../../src/hooks/SimpleRewards.sol";

/// @title SimpleRewards Security Test Suite
/// @notice Security-focused testing with attack scenarios targeting privilege escalation and access control
/// @dev Tests manager authorization bypass, reentrancy, and economic attacks
contract SimpleRewardsAttackTest is Test {
    Flywheel public flywheel;
    SimpleRewards public hook;
    MockERC20 public token;

    address public manager = address(0x1000);
    address public attacker = address(0xBAD);
    address public victim = address(0x2000);
    address public accomplice = address(0x3000);

    address public campaign;
    uint256 public constant INITIAL_TOKEN_BALANCE = 1000e18;
    uint256 public constant PAYOUT_AMOUNT = 100e18;

    function setUp() public {
        // Deploy contracts
        flywheel = new Flywheel();
        hook = new SimpleRewards(address(flywheel));

        // Deploy token with initial holders
        address[] memory initialHolders = new address[](4);
        initialHolders[0] = manager;
        initialHolders[1] = address(this);
        initialHolders[2] = attacker;
        initialHolders[3] = victim;
        token = new MockERC20(initialHolders);

        // Create campaign with manager
        bytes memory hookData = abi.encode(manager, manager, "");
        campaign = flywheel.createCampaign(address(hook), 1, hookData);

        // Fund campaign
        vm.prank(manager);
        token.transfer(campaign, INITIAL_TOKEN_BALANCE);

        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
    }

    // =============================================================
    //                    PRIVILEGE ESCALATION ATTACKS
    // =============================================================

    /// @notice Test manager authorization bypass attempts
    function test_security_managerAuthorizationBypass() public {
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: attacker, amount: PAYOUT_AMOUNT, extraData: ""});
        bytes memory hookData = abi.encode(payouts);

        // Direct attack: Attacker tries to call payout functions
        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(attacker);
        flywheel.send(campaign, address(token), hookData);

        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(attacker);
        flywheel.allocate(campaign, address(token), hookData);

        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(attacker);
        flywheel.distribute(campaign, address(token), hookData);

        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(attacker);
        flywheel.deallocate(campaign, address(token), hookData);
    }

    /// @notice Test campaign manager replacement attack
    function test_security_campaignManagerReplacement() public {
        // Attacker tries to create new campaign with themselves as manager
        bytes memory maliciousHookData = abi.encode(attacker, attacker, "");
        address attackerCampaign = flywheel.createCampaign(address(hook), 2, maliciousHookData);

        // Verify attacker is manager of their own campaign
        assertEq(hook.managers(attackerCampaign), attacker);

        // But attacker cannot control original campaign
        assertEq(hook.managers(campaign), manager);

        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: attacker, amount: PAYOUT_AMOUNT, extraData: ""});
        bytes memory hookData = abi.encode(payouts);

        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(attacker);
        flywheel.send(campaign, address(token), hookData);
    }

    /// @notice Test zero address manager exploitation
    function test_security_zeroAddressManagerExploitation() public {
        // Create campaign with zero address manager
        bytes memory hookData = abi.encode(address(0), address(0), "");
        address zeroCampaign = flywheel.createCampaign(address(hook), 3, hookData);

        // Fund the campaign
        token.transfer(zeroCampaign, INITIAL_TOKEN_BALANCE);

        // Note: Can't activate campaign with zero address manager, so test will fail at campaign status level
        // This is actually good - zero address manager campaigns remain inactive

        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: attacker, amount: PAYOUT_AMOUNT, extraData: ""});
        bytes memory payoutData = abi.encode(payouts);

        // Attacker cannot exploit zero address manager - campaign remains inactive
        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(attacker);
        flywheel.send(zeroCampaign, address(token), payoutData);

        // Even msg.sender = address(0) fails - campaign remains inactive
        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        vm.prank(address(0));
        flywheel.send(zeroCampaign, address(token), payoutData);
    }

    // =============================================================
    //                    REENTRANCY ATTACKS
    // =============================================================

    /// @notice Test reentrancy via malicious recipient
    function test_security_reentrancyViaMaliciousRecipient() public {
        // Deploy malicious contract that reenters on token receive
        MaliciousRecipient maliciousRecipient = new MaliciousRecipient(address(hook), campaign);

        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: address(maliciousRecipient), amount: PAYOUT_AMOUNT, extraData: ""});
        bytes memory hookData = abi.encode(payouts);

        // Malicious recipient receives tokens normally (ERC20 doesn't trigger callbacks)
        // The reentrancy protection is at the Flywheel level for state-modifying functions
        vm.prank(manager);
        flywheel.send(campaign, address(token), hookData);

        // Verify the malicious recipient received tokens
        assertEq(token.balanceOf(address(maliciousRecipient)), PAYOUT_AMOUNT);
    }

    /// @notice Test cross-function reentrancy
    function test_security_crossFunctionReentrancy() public {
        CrossFunctionReentrancyAttacker attacker_contract =
            new CrossFunctionReentrancyAttacker(address(hook), address(flywheel), campaign);

        // Fund attacker contract so it can pay for gas
        token.transfer(address(attacker_contract), 100e18);

        // Attacker tries to exploit cross-function reentrancy
        vm.prank(manager);
        vm.expectRevert(); // Should fail due to access control or reentrancy protection
        attacker_contract.attemptCrossFunctionReentrancy();
    }

    // =============================================================
    //                    ECONOMIC ATTACKS
    // =============================================================

    /// @notice Test campaign fund drainage attack
    function test_security_campaignFundDrainage() public {
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({
            recipient: attacker,
            amount: INITIAL_TOKEN_BALANCE, // Attempt to drain entire campaign
            extraData: ""
        });
        bytes memory hookData = abi.encode(payouts);

        uint256 attackerBalanceBefore = token.balanceOf(attacker);

        // Manager (could be compromised) drains campaign
        vm.prank(manager);
        flywheel.send(campaign, address(token), hookData);

        // Verify drainage succeeded (this is expected behavior with compromised manager)
        assertEq(token.balanceOf(attacker), attackerBalanceBefore + INITIAL_TOKEN_BALANCE);
        assertEq(token.balanceOf(campaign), 0);
    }

    /// @notice Test batch payout manipulation
    function test_security_batchPayoutManipulation() public {
        // Create large batch with hidden malicious recipient
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](10);

        // Fill with legitimate-looking recipients
        for (uint256 i = 0; i < 9; i++) {
            payouts[i] = Flywheel.Payout({recipient: victim, amount: 1e18, extraData: ""});
        }

        // Hidden large payout to attacker
        payouts[9] =
            Flywheel.Payout({
                recipient: attacker,
                amount: 900e18, // Large amount hidden in batch
                extraData: ""
            });

        bytes memory hookData = abi.encode(payouts);

        uint256 attackerBalanceBefore = token.balanceOf(attacker);

        vm.prank(manager);
        flywheel.send(campaign, address(token), hookData);

        // Attacker received large hidden payout
        assertEq(token.balanceOf(attacker), attackerBalanceBefore + 900e18);
    }

    /// @notice Test allocation/distribution timing attack
    function test_security_allocationDistributionTimingAttack() public {
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: attacker, amount: PAYOUT_AMOUNT, extraData: ""});
        bytes memory hookData = abi.encode(payouts);

        // Allocate funds
        vm.prank(manager);
        flywheel.allocate(campaign, address(token), hookData);

        // Verify allocation recorded in core flywheel
        assertEq(flywheel.allocatedPayout(campaign, address(token), bytes32(bytes20(attacker))), PAYOUT_AMOUNT);

        // Manager could manipulate by deallocating before victim claims
        vm.prank(manager);
        flywheel.deallocate(campaign, address(token), hookData);

        // Verify deallocation
        assertEq(flywheel.allocatedPayout(campaign, address(token), bytes32(bytes20(attacker))), 0);

        // Attacker received no tokens despite initial allocation
        assertEq(token.balanceOf(attacker), 1000000e18); // Only initial balance from MockERC20
    }

    // =============================================================
    //                    ACCESS CONTROL ATTACKS
    // =============================================================

    /// @notice Test campaign status manipulation by non-manager
    function test_security_statusManipulationByNonManager() public {
        // Attacker tries to change campaign status
        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(attacker);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.INACTIVE, "");

        // Verify status unchanged
        assertEq(uint256(flywheel.campaignStatus(campaign)), uint256(Flywheel.CampaignStatus.ACTIVE));
    }

    /// @notice Test fund withdrawal by non-manager
    function test_security_fundWithdrawalByNonManager() public {
        // Move campaign to finalized state first
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");

        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");

        // Attacker tries to withdraw funds
        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(attacker);
        flywheel.withdrawFunds(
            campaign, address(token), abi.encode(Flywheel.Payout({recipient: attacker, amount: 100e18, extraData: ""}))
        );
    }

    // =============================================================
    //                    HOOK DATA MANIPULATION
    // =============================================================

    /// @notice Test malformed hook data attack
    function test_security_malformedHookDataAttack() public {
        // Malformed hook data that could cause decode errors
        bytes memory malformedData = hex"deadbeef";

        vm.prank(manager);
        vm.expectRevert(); // Should revert on decode
        flywheel.send(campaign, address(token), malformedData);
    }

    /// @notice Test empty payouts array exploitation
    function test_security_emptyPayoutsExploitation() public {
        Flywheel.Payout[] memory emptyPayouts = new Flywheel.Payout[](0);
        bytes memory hookData = abi.encode(emptyPayouts);

        uint256 campaignBalanceBefore = token.balanceOf(campaign);

        // Empty payouts should not cause issues
        vm.prank(manager);
        flywheel.send(campaign, address(token), hookData);

        // Campaign balance should be unchanged
        assertEq(token.balanceOf(campaign), campaignBalanceBefore);
    }

    // =============================================================
    //                    CAMPAIGN ISOLATION ATTACKS
    // =============================================================

    /// @notice Test cross-campaign privilege escalation
    function test_security_crossCampaignPrivilegeEscalation() public {
        // Create second campaign with different manager
        bytes memory hookData2 = abi.encode(attacker, attacker, "");
        address attackerCampaign = flywheel.createCampaign(address(hook), 4, hookData2);

        // Fund attacker's campaign
        vm.prank(attacker);
        token.transfer(attackerCampaign, INITIAL_TOKEN_BALANCE);

        vm.prank(attacker);
        flywheel.updateStatus(attackerCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Attacker (manager of their campaign) tries to control original campaign
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: attacker, amount: PAYOUT_AMOUNT, extraData: ""});
        bytes memory hookData = abi.encode(payouts);

        vm.expectRevert(SimpleRewards.Unauthorized.selector);
        vm.prank(attacker);
        flywheel.send(campaign, address(token), hookData); // Should fail - different campaign

        // But attacker can control their own campaign
        vm.prank(attacker);
        flywheel.send(attackerCampaign, address(token), hookData); // Should succeed
    }
}

// =============================================================
//                    MALICIOUS CONTRACTS
// =============================================================

/// @notice Malicious recipient that attempts reentrancy on token receive
contract MaliciousRecipient {
    SimpleRewards public hook;
    address public campaign;
    bool public attacking;

    constructor(address _hook, address _campaign) {
        hook = SimpleRewards(_hook);
        campaign = _campaign;
    }

    function onTokenReceived() external {
        if (!attacking) {
            attacking = true;
            // Attempt reentrancy by calling hook functions
            try hook.managers(campaign) {} catch {}
            attacking = false;
        }
    }
}

/// @notice Contract that attempts cross-function reentrancy
contract CrossFunctionReentrancyAttacker {
    SimpleRewards public hook;
    Flywheel public flywheel;
    address public campaign;
    bool public attacking;

    constructor(address _hook, address _flywheel, address _campaign) {
        hook = SimpleRewards(_hook);
        flywheel = Flywheel(_flywheel);
        campaign = _campaign;
    }

    function attemptCrossFunctionReentrancy() external {
        // This would require being the manager, which this contract is not
        // So this will fail with Unauthorized
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: address(this), amount: 100e18, extraData: ""});
        bytes memory hookData = abi.encode(payouts);

        flywheel.send(campaign, address(0x1), hookData);
    }

    receive() external payable {
        if (!attacking) {
            attacking = true;
            // Attempt cross-function reentrancy
            try hook.managers(campaign) {} catch {}
            attacking = false;
        }
    }
}
