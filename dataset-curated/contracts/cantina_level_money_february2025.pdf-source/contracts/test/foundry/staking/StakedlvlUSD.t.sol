// SPDX-License-Identifier: MIT
pragma solidity >=0.8;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import {SigUtils} from "../../utils/SigUtils.sol";

import "../../../src/lvlUSD.sol";
import {StakedlvlUSD} from "../../../src/StakedlvlUSD.sol";
import {IlvlUSD} from "../../../src/interfaces/IlvlUSD.sol";
import "../../../src/interfaces/IERC20Events.sol";
import "../../../src/interfaces/IStakedlvlUSDCooldown.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {IERC20 as IERC20v4} from "@openzeppelin-4.9.0/contracts/interfaces/IERC20.sol";

contract StakedlvlUSDTest is Test, IERC20Events {
    lvlUSD public lvlUSDToken;
    StakedlvlUSD public stakedlvlUSD;
    SigUtils public sigUtilslvlUSD;
    SigUtils public sigUtilsStakedlvlUSD;

    address public owner;
    address public rewarder;
    address public freezer;
    address public alice;
    address public bob;
    address public greg;

    bytes32 REWARDER_ROLE = keccak256("REWARDER_ROLE");
    bytes32 FREEZER_ROLE = keccak256("FREEZER_ROLE");
    bytes32 WITHDRAW_FROM_FREEZER_ROLE =
        keccak256("WITHDRAW_FROM_FREEZER_ROLE");

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event RewardsReceived(uint256 indexed amount);

    function setUp() public virtual {
        lvlUSDToken = new lvlUSD(address(this));

        alice = vm.addr(0xB44DE);
        bob = vm.addr(0x1DE);
        greg = vm.addr(0x6ED);
        owner = vm.addr(0xA11CE);
        rewarder = vm.addr(0x1DEA);
        freezer = vm.addr(0x56781A);

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(greg, "greg");
        vm.label(owner, "owner");
        vm.label(rewarder, "rewarder");
        vm.label(freezer, "freezer");

        vm.prank(owner);
        stakedlvlUSD = new StakedlvlUSD(
            IERC20v4(address(lvlUSDToken)),
            rewarder,
            owner
        );

        sigUtilslvlUSD = new SigUtils(lvlUSDToken.DOMAIN_SEPARATOR());
        sigUtilsStakedlvlUSD = new SigUtils(stakedlvlUSD.DOMAIN_SEPARATOR());

        lvlUSDToken.setMinter(address(this));
    }

    function _mintApproveDeposit(address staker, uint256 amount) internal {
        lvlUSDToken.setMinter(address(this));
        lvlUSDToken.mint(staker, amount);

        vm.startPrank(staker);
        lvlUSDToken.approve(address(stakedlvlUSD), amount);

        // vm.expectEmit(true, true, true, false);
        emit Deposit(staker, staker, amount, amount);

        stakedlvlUSD.deposit(amount, staker);
        vm.stopPrank();
    }

    // TODO: why is this call failing?
    function _redeem(address staker, uint256 amount) internal {
        vm.startPrank(staker);

        // vm.expectEmit(true, true, true, false);
        emit Withdraw(staker, staker, staker, amount, amount);

        stakedlvlUSD.redeem(amount, staker, staker);
        vm.stopPrank();
    }

    function _transferRewards(
        uint256 amount,
        uint256 expectedNewVestingAmount
    ) internal {
        lvlUSDToken.mint(address(rewarder), amount);
        vm.startPrank(rewarder);

        lvlUSDToken.approve(address(stakedlvlUSD), amount);

        // vm.expectEmit(true, false, false, true);
        emit Transfer(rewarder, address(stakedlvlUSD), amount);
        // vm.expectEmit(true, false, false, false);
        emit RewardsReceived(amount);

        stakedlvlUSD.transferInRewards(amount);

        assertApproxEqAbs(
            stakedlvlUSD.getUnvestedAmount(),
            expectedNewVestingAmount,
            1
        );
        vm.stopPrank();
    }

    function _assertVestedAmountIs(uint256 amount) internal {
        assertApproxEqAbs(stakedlvlUSD.totalAssets(), amount, 2);
    }

    function testInitialStake() public {
        uint256 amount = 100 ether;
        _mintApproveDeposit(alice, amount);

        assertEq(lvlUSDToken.balanceOf(alice), 0);
        assertEq(lvlUSDToken.balanceOf(address(stakedlvlUSD)), amount);
        assertEq(stakedlvlUSD.balanceOf(alice), amount);
    }

    function testInitialStakeBelowMin() public {
        uint256 amount = 0.99 ether;
        lvlUSDToken.mint(alice, amount);
        vm.startPrank(alice);
        lvlUSDToken.approve(address(stakedlvlUSD), amount);
        vm.expectRevert(IStakedlvlUSD.MinSharesViolation.selector);
        stakedlvlUSD.deposit(amount, alice);

        assertEq(lvlUSDToken.balanceOf(alice), amount);
        assertEq(lvlUSDToken.balanceOf(address(stakedlvlUSD)), 0);
        assertEq(stakedlvlUSD.balanceOf(alice), 0);
    }

    function testCantWithdrawBelowMinShares() public {
        _mintApproveDeposit(alice, 1 ether);

        vm.startPrank(alice);
        lvlUSDToken.approve(address(stakedlvlUSD), 0.01 ether);
        vm.expectRevert();
        stakedlvlUSD.redeem(0.5 ether, alice, alice);
    }

    function testCannotStakeWithoutApproval() public {
        uint256 amount = 100 ether;
        lvlUSDToken.mint(alice, amount);

        vm.startPrank(alice);
        vm.expectRevert("ERC20: insufficient allowance");
        stakedlvlUSD.deposit(amount, alice);
        vm.stopPrank();

        assertEq(lvlUSDToken.balanceOf(alice), amount);
        assertEq(lvlUSDToken.balanceOf(address(stakedlvlUSD)), 0);
        assertEq(stakedlvlUSD.balanceOf(alice), 0);
    }

    function testStakeUnstake() public {
        vm.prank(owner);
        stakedlvlUSD.setCooldownDuration(0 days);
        uint256 amount = 100 ether;
        _mintApproveDeposit(alice, amount);

        assertEq(lvlUSDToken.balanceOf(alice), 0);
        assertEq(lvlUSDToken.balanceOf(address(stakedlvlUSD)), amount);
        assertEq(stakedlvlUSD.balanceOf(alice), amount);

        _redeem(alice, amount); // TODO: figure out why this isn't working

        assertEq(lvlUSDToken.balanceOf(alice), amount);
        assertEq(lvlUSDToken.balanceOf(address(stakedlvlUSD)), 0);
        assertEq(stakedlvlUSD.balanceOf(alice), 0);
    }

    function testOnlyRewarderCanReward() public {
        uint256 amount = 100 ether;
        uint256 rewardAmount = 0.5 ether;
        _mintApproveDeposit(alice, amount);

        lvlUSDToken.mint(bob, rewardAmount);
        vm.startPrank(bob);

        vm.expectRevert(
            "AccessControl: account 0x72c7a47c5d01bddf9067eabb345f5daabdead13f is missing role 0xbeec13769b5f410b0584f69811bfd923818456d5edcf426b0e31cf90eed7a3f6"
        );
        stakedlvlUSD.transferInRewards(rewardAmount);
        vm.stopPrank();
        assertEq(lvlUSDToken.balanceOf(alice), 0);
        assertEq(lvlUSDToken.balanceOf(address(stakedlvlUSD)), amount);
        assertEq(stakedlvlUSD.balanceOf(alice), amount);
        _assertVestedAmountIs(amount);
        assertEq(lvlUSDToken.balanceOf(bob), rewardAmount);
    }

    function testStakingAndUnstakingBeforeAfterReward() public {
        vm.prank(owner);
        stakedlvlUSD.setCooldownDuration(0 days);
        uint256 amount = 100 ether;
        uint256 rewardAmount = 100 ether;
        _mintApproveDeposit(alice, amount);
        _transferRewards(rewardAmount, rewardAmount);
        _redeem(alice, amount);
        assertEq(lvlUSDToken.balanceOf(alice), amount);
        assertEq(stakedlvlUSD.totalSupply(), 0);
    }

    function testFuzzNoJumpInVestedBalance(uint256 amount) public {
        vm.assume(amount > 0 && amount < 1e60);
        _transferRewards(amount, amount);
        vm.warp(block.timestamp + 4 hours);
        _assertVestedAmountIs(amount / 2);
        assertEq(lvlUSDToken.balanceOf(address(stakedlvlUSD)), amount);
    }

    function testOwnerCannotRescuelvlUSD() public {
        uint256 amount = 100 ether;
        _mintApproveDeposit(alice, amount);
        bytes4 selector = bytes4(keccak256("InvalidToken()"));
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(selector));
        stakedlvlUSD.rescueTokens(address(lvlUSDToken), amount, owner);
    }

    function testOwnerCanRescuestlvlUSD() public {
        uint256 amount = 100 ether;
        _mintApproveDeposit(alice, amount);
        vm.prank(alice);
        stakedlvlUSD.transfer(address(stakedlvlUSD), amount);
        assertEq(stakedlvlUSD.balanceOf(owner), 0);
        vm.startPrank(owner);
        stakedlvlUSD.rescueTokens(address(stakedlvlUSD), amount, owner);
        assertEq(stakedlvlUSD.balanceOf(owner), amount);
    }

    function testOwnerCanChangeRewarder() public {
        assertTrue(stakedlvlUSD.hasRole(REWARDER_ROLE, address(rewarder)));
        address newRewarder = address(0x123);
        vm.startPrank(owner);
        stakedlvlUSD.revokeRole(REWARDER_ROLE, rewarder);
        stakedlvlUSD.grantRole(REWARDER_ROLE, newRewarder);
        assertTrue(!stakedlvlUSD.hasRole(REWARDER_ROLE, address(rewarder)));
        assertTrue(stakedlvlUSD.hasRole(REWARDER_ROLE, newRewarder));
        vm.stopPrank();

        lvlUSDToken.mint(rewarder, 1 ether);
        lvlUSDToken.mint(newRewarder, 1 ether);

        vm.startPrank(rewarder);
        lvlUSDToken.approve(address(stakedlvlUSD), 1 ether);
        vm.expectRevert(
            "AccessControl: account 0x5c664540bc6bb6b22e9d1d3d630c73c02edd94b7 is missing role 0xbeec13769b5f410b0584f69811bfd923818456d5edcf426b0e31cf90eed7a3f6"
        );
        stakedlvlUSD.transferInRewards(1 ether);
        vm.stopPrank();

        vm.startPrank(newRewarder);
        lvlUSDToken.approve(address(stakedlvlUSD), 1 ether);
        stakedlvlUSD.transferInRewards(1 ether);
        vm.stopPrank();

        assertEq(lvlUSDToken.balanceOf(address(stakedlvlUSD)), 1 ether);
        assertEq(lvlUSDToken.balanceOf(rewarder), 1 ether);
        assertEq(lvlUSDToken.balanceOf(newRewarder), 0);
    }

    function testlvlUSDValuePerStlvlUSD() public {
        vm.prank(owner);
        stakedlvlUSD.setCooldownDuration(0 days);
        _mintApproveDeposit(alice, 100 ether);
        _transferRewards(100 ether, 100 ether);
        vm.warp(block.timestamp + 4 hours);
        _assertVestedAmountIs(150 ether);
        assertEq(stakedlvlUSD.convertToAssets(1 ether), 1.5 ether - 1);
        assertEq(stakedlvlUSD.totalSupply(), 100 ether);
        // rounding
        _mintApproveDeposit(bob, 75 ether);
        _assertVestedAmountIs(225 ether);
        assertEq(stakedlvlUSD.balanceOf(alice), 100 ether);
        assertEq(stakedlvlUSD.balanceOf(bob), 50 ether);
        assertEq(stakedlvlUSD.convertToAssets(1 ether), 1.5 ether - 1);

        vm.warp(block.timestamp + 8 hours);

        uint256 vestedAmount = 275 ether;
        _assertVestedAmountIs(vestedAmount);

        assertApproxEqAbs(
            stakedlvlUSD.convertToAssets(1 ether),
            (vestedAmount * 1 ether) / 150 ether,
            1
        );

        // rounding
        _redeem(bob, stakedlvlUSD.balanceOf(bob));

        _redeem(alice, 100 ether);

        assertEq(stakedlvlUSD.balanceOf(alice), 0);
        assertEq(stakedlvlUSD.balanceOf(bob), 0);
        assertEq(stakedlvlUSD.totalSupply(), 0);

        assertApproxEqAbs(
            lvlUSDToken.balanceOf(alice),
            (vestedAmount * 2) / 3,
            2
        );

        assertApproxEqAbs(lvlUSDToken.balanceOf(bob), vestedAmount / 3, 2);

        assertApproxEqAbs(lvlUSDToken.balanceOf(address(stakedlvlUSD)), 0, 1);
    }

    function testFairStakeAndUnstakePrices() public {
        vm.prank(owner);
        stakedlvlUSD.setCooldownDuration(0 days);
        uint256 aliceAmount = 100 ether;
        uint256 bobAmount = 1000 ether;
        uint256 rewardAmount = 200 ether;
        _mintApproveDeposit(alice, aliceAmount);
        _transferRewards(rewardAmount, rewardAmount);
        vm.warp(block.timestamp + 4 hours);
        _mintApproveDeposit(bob, bobAmount);
        vm.warp(block.timestamp + 4 hours);
        _redeem(alice, aliceAmount);
        // _assertVestedAmountIs(bobAmount + (rewardAmount * 5) / 12);
    }

    /// forge-config: default.fuzz.max-test-rejects = 2000000
    function testFuzzFairStakeAndUnstakePrices(
        uint256 amount1,
        uint256 amount2,
        uint256 amount3,
        uint256 rewardAmount,
        uint256 waitSeconds
    ) public {
        vm.prank(owner);
        stakedlvlUSD.setCooldownDuration(0 days);
        //uint256 waitSeconds = 5 hours; // todo: make this a function parameter for fuzz testing
        vm.assume(
            amount1 >= 100 ether &&
                amount2 > 0 &&
                amount3 > 0 &&
                rewardAmount > 0 &&
                waitSeconds < 9 hours &&
                // 100 trillion USD with 18 decimals
                amount1 < 1e32 &&
                amount2 < 1e32 &&
                amount3 < 1e32 &&
                rewardAmount < 1e32
        );

        uint256 totalContributions = amount1;

        _mintApproveDeposit(alice, amount1);

        _transferRewards(rewardAmount, rewardAmount);

        vm.warp(block.timestamp + waitSeconds);

        uint256 vestedAmount;
        if (waitSeconds > 8 hours) {
            vestedAmount = amount1 + rewardAmount;
        } else {
            vestedAmount =
                amount1 +
                rewardAmount -
                (rewardAmount * (8 hours - waitSeconds)) /
                8 hours;
        }

        _assertVestedAmountIs(vestedAmount);

        uint256 bobStakedlvlUSD = (amount2 * (amount1 + 1)) /
            (vestedAmount + 1);
        if (bobStakedlvlUSD > 0) {
            _mintApproveDeposit(bob, amount2);
            totalContributions += amount2;
        }

        vm.warp(block.timestamp + waitSeconds);

        if (waitSeconds > 4 hours) {
            vestedAmount = totalContributions + rewardAmount;
        } else {
            vestedAmount =
                totalContributions +
                rewardAmount -
                ((4 hours - waitSeconds) * rewardAmount) /
                4 hours;
        }

        _assertVestedAmountIs(vestedAmount);

        uint256 gregStakedlvlUSD = (amount3 *
            (stakedlvlUSD.totalSupply() + 1)) / (vestedAmount + 1);
        if (gregStakedlvlUSD > 0) {
            _mintApproveDeposit(greg, amount3);
            totalContributions += amount3;
        }

        vm.warp(block.timestamp + 8 hours);

        vestedAmount = totalContributions + rewardAmount;

        _assertVestedAmountIs(vestedAmount);

        uint256 lvlusdPerStakedlvlUSDBefore = stakedlvlUSD.convertToAssets(
            1 ether
        );
        uint256 bobUnstakeAmount = (stakedlvlUSD.balanceOf(bob) *
            (vestedAmount + 1)) / (stakedlvlUSD.totalSupply() + 1);
        uint256 gregUnstakeAmount = (stakedlvlUSD.balanceOf(greg) *
            (vestedAmount + 1)) / (stakedlvlUSD.totalSupply() + 1);

        if (bobUnstakeAmount > 0) _redeem(bob, stakedlvlUSD.balanceOf(bob));
        uint256 lvlusdPerStakedlvlUSDAfter = stakedlvlUSD.convertToAssets(
            1 ether
        );
        if (lvlusdPerStakedlvlUSDAfter != 0)
            assertApproxEqAbs(
                lvlusdPerStakedlvlUSDAfter,
                lvlusdPerStakedlvlUSDBefore,
                1 ether
            );

        if (gregUnstakeAmount > 0) _redeem(greg, stakedlvlUSD.balanceOf(greg));
        lvlusdPerStakedlvlUSDAfter = stakedlvlUSD.convertToAssets(1 ether);
        if (lvlusdPerStakedlvlUSDAfter != 0)
            assertApproxEqAbs(
                lvlusdPerStakedlvlUSDAfter,
                lvlusdPerStakedlvlUSDBefore,
                1 ether
            );

        _redeem(alice, amount1);

        assertEq(stakedlvlUSD.totalSupply(), 0);
        assertApproxEqAbs(stakedlvlUSD.totalAssets(), 0, 10 ** 12);
    }

    function testTransferRewardsFailsInsufficientBalance() public {
        lvlUSDToken.mint(address(rewarder), 99);
        vm.startPrank(rewarder);

        lvlUSDToken.approve(address(stakedlvlUSD), 100);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        stakedlvlUSD.transferInRewards(100);
        vm.stopPrank();
    }

    function testTransferRewardsFailsZeroAmount() public {
        lvlUSDToken.mint(address(rewarder), 100);
        vm.startPrank(rewarder);

        lvlUSDToken.approve(address(stakedlvlUSD), 100);

        vm.expectRevert(IStakedlvlUSD.InvalidAmount.selector);
        stakedlvlUSD.transferInRewards(0);
        vm.stopPrank();
    }

    function testDecimalsIs18() public {
        assertEq(stakedlvlUSD.decimals(), 18);
    }

    function testMintWithSlippageCheck(uint256 amount) public {
        amount = bound(amount, 1 ether, type(uint256).max / 2);
        lvlUSDToken.mint(alice, amount * 2);

        assertEq(stakedlvlUSD.balanceOf(alice), 0);

        vm.startPrank(alice);
        lvlUSDToken.approve(address(stakedlvlUSD), amount);
        // vm.expectEmit(true, true, true, true);
        emit Deposit(alice, alice, amount, amount);
        stakedlvlUSD.mint(amount, alice);

        assertEq(stakedlvlUSD.balanceOf(alice), amount);

        lvlUSDToken.approve(address(stakedlvlUSD), amount);
        // vm.expectEmit(true, true, true, true);
        emit Deposit(alice, alice, amount, amount);
        stakedlvlUSD.mint(amount, alice);

        assertEq(stakedlvlUSD.balanceOf(alice), amount * 2);
    }

    function testMintToDiffRecipient() public {
        lvlUSDToken.mint(alice, 1 ether);

        vm.startPrank(alice);

        lvlUSDToken.approve(address(stakedlvlUSD), 1 ether);

        stakedlvlUSD.deposit(1 ether, bob);

        assertEq(stakedlvlUSD.balanceOf(alice), 0);
        assertEq(stakedlvlUSD.balanceOf(bob), 1 ether);
    }

    function testCannotTransferRewardsWhileVesting() public {
        _transferRewards(100 ether, 100 ether);
        vm.warp(block.timestamp + 4 hours);
        _assertVestedAmountIs(50 ether);
        vm.prank(rewarder);
        vm.expectRevert(IStakedlvlUSD.StillVesting.selector);
        stakedlvlUSD.transferInRewards(100 ether);
        _assertVestedAmountIs(50 ether);
        assertEq(stakedlvlUSD.vestingAmount(), 100 ether);
    }

    function testDummy() public {
        _transferRewards(100 ether, 100 ether);
    }

    function testCanTransferRewardsAfterVesting() public {
        _transferRewards(100 ether, 100 ether);
        vm.warp(block.timestamp + 8 hours);
        _assertVestedAmountIs(100 ether);
        _transferRewards(100 ether, 100 ether);
        vm.warp(block.timestamp + 16 hours);
        _assertVestedAmountIs(200 ether);
    }

    function testDonationAttack() public {
        uint256 initialStake = 1 ether;
        uint256 donationAmount = 10_000_000_000 ether;
        uint256 bobStake = 100 ether;
        _mintApproveDeposit(alice, initialStake);
        assertEq(stakedlvlUSD.totalSupply(), initialStake);
        lvlUSDToken.mint(alice, donationAmount);
        vm.prank(alice);
        lvlUSDToken.transfer(address(stakedlvlUSD), donationAmount);
        assertEq(stakedlvlUSD.totalSupply(), initialStake);
        assertEq(
            lvlUSDToken.balanceOf(address(stakedlvlUSD)),
            initialStake + donationAmount
        );
        _mintApproveDeposit(bob, bobStake);
        uint256 bobStlvlUSDBal = stakedlvlUSD.balanceOf(bob);
        uint256 bobStlvlUSDExpectedBal = (bobStake * initialStake) /
            (initialStake + donationAmount);
        assertApproxEqAbs(bobStlvlUSDBal, bobStlvlUSDExpectedBal, 1e9);
        assertTrue(bobStlvlUSDBal > 0);
    }

    function testCoolDownSharesAndUnstake() public {
        vm.startPrank(owner);
        // set cooldown duration to be 7 days
        stakedlvlUSD.setCooldownDuration(7 days);
        vm.stopPrank();

        // TODO: find out who msg.sender is when startPrank is not called
        uint256 amount = 100 ether;
        _mintApproveDeposit(alice, amount);
        assertEq(stakedlvlUSD.balanceOf(alice), amount);

        vm.startPrank(alice);

        // initiate share cooldown process in anticipation of unstaking
        stakedlvlUSD.cooldownShares(10 ether);

        // check that shares have been transferred from Alice
        assertEq(stakedlvlUSD.balanceOf(alice), 90 ether);

        // check that shares have indeed been escrowed to the silo
        assertEq(lvlUSDToken.balanceOf(address(stakedlvlUSD.silo())), 10 ether);

        // check that assets cannot be unstaked before cooldown period ends
        vm.warp(6 days);
        vm.expectRevert(IStakedlvlUSDCooldown.InvalidCooldown.selector);
        stakedlvlUSD.unstake(alice);

        // check that assets can be unstaked after cooldown period ends
        vm.warp(8 days);
        stakedlvlUSD.unstake(alice);
        assertEq(lvlUSDToken.balanceOf(alice), 10 ether);
        vm.stopPrank();
    }
}
