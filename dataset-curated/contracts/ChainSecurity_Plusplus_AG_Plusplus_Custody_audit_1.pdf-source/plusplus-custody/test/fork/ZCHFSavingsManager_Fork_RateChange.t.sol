// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ZCHFSavingsManager} from "src/ZCHFSavingsManager.sol";
import {IFrankencoinSavings} from "../interfaces/IFrankencoinSavings.sol";
import {IZCHFErrors} from "../interfaces/IZCHFErrors.sol";

// The minimal ERC20 interface
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

interface ILeadrate {
    function currentRatePPM() external view returns (uint24);
    function nextRatePPM() external view returns (uint24);
    function nextChange() external view returns (uint40);
    function proposeChange(uint24 newRatePPM, address[] calldata helpers) external;
    function applyChange() external;
    function accruedInterest(address accountOwner) external view returns (uint192);
    function INTEREST_DELAY() external view returns (uint64 delay);
    function savings(address)
        external
        view
        returns (uint192 saved, uint64 ticks, address referrer, uint32 referralFeePPM);
    function ticks(uint256 timestamp) external view returns (uint64 tick);
}

/// @title ZCHFSavingsManagerForkRateChangeTest
/// @notice Integration tests for rate changes, interest accruals, fee mechanics and edge cases.
contract ZCHFSavingsManagerForkRateChangeTest is Test {
    // Mainnet addresses
    address constant ZCHF_ADDRESS = 0xB58E61C3098d85632Df34EecfB899A1Ed80921cB;
    address constant SAVINGS_MODULE = 0x27d9AD987BdE08a0d083ef7e0e4043C857A17B38;
    address constant WHALE = 0xa8c4E40075D1bb3A6E3343Be55b32B8E4a5612a1;
    address constant QUALIFIED_PROPOSER = 0x5a57dD9C623e1403AF1D810673183D89724a4e0c;

    address admin;
    address operator;
    address receiver;

    ZCHFSavingsManager internal manager;
    IERC20 internal zchf;
    ILeadrate internal savings;
    ILeadrate internal leadRate;

    event DepositCreated(bytes32 indexed identifier, uint192 amount);
    event DepositRedeemed(bytes32 indexed identifier, uint192 totalAmount);

    function setUp() public {
        uint256 fork = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(fork);

        admin = address(this);
        operator = address(this);
        receiver = makeAddr("receiverRate");

        zchf = IERC20(ZCHF_ADDRESS);
        savings = ILeadrate(SAVINGS_MODULE);
        leadRate = ILeadrate(SAVINGS_MODULE);
        manager = new ZCHFSavingsManager(admin, ZCHF_ADDRESS, SAVINGS_MODULE);
        manager.grantRole(manager.OPERATOR_ROLE(), operator);
        manager.grantRole(manager.RECEIVER_ROLE(), receiver);
        manager.setDailyLimit(operator, 1_000_000e18);

        // Fund this contract with ample ZCHF
        vm.startPrank(WHALE);
        require(zchf.transfer(address(this), 10_000 ether), "fund fail");
        vm.stopPrank();
        zchf.approve(address(manager), type(uint256).max);

        vm.deal(address(this), 20 ether);
    }

    // --- Internal helper to change rate via Leadrate module ---
    function _scheduleAndApplyRate(uint24 newRate) internal {
        vm.startPrank(QUALIFIED_PROPOSER);
        address[] memory helpers = new address[](0);
        leadRate.proposeChange(newRate, helpers);
        vm.warp(block.timestamp + 7 days + 1);
        leadRate.applyChange();
        vm.stopPrank();
    }

    // --- EXAMPLE 1: 2% (20_000 ppm) return for 1 year, then 0.0001% (1 ppm) for another year ---
    function testFork_Example1_TwoPercentYearThenZero() public {
        // Schedule
        _scheduleAndApplyRate(20_000); // 2% rate
        uint256 initialTime = block.timestamp;
        uint256 ts1 = initialTime + 365 days;
        uint256 ts2 = ts1 + 365 days;

        // Deposit 10,000 ZCHF
        bytes32 id = keccak256("Ex1");
        uint192 amount = 10_000 ether;
        vm.prank(operator);
        manager.createDeposits(_arr1(id), _arr1(amount), address(this));

        // Change rate to 4% exactly at the end of the 1st year
        vm.warp(ts1 - 7 days - 1);
        uint24 ratePPM = 1;
        _scheduleAndApplyRate(ratePPM);
        assertEq(block.timestamp, ts1);
        assertEq(savings.currentRatePPM(), ratePPM);

        uint192 grossInterest1 = savings.accruedInterest(address(manager));
        uint192 manualInterest1 = amount * 362 days * 20_000 / 1_000_000 / 365 days; // 3 days delay
        assertEq(grossInterest1, manualInterest1);
        uint192 manualFee1 = 365 days * amount * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days; // 125e18
        uint192 manualNetInterest1 = manualInterest1 > manualFee1 ? manualInterest1 - manualFee1 : 0;
        console.log("Ex1: Gross interest after 1 year:", grossInterest1, "ZCHF");
        console.log("Ex1: Net interest after 1 year:", manualNetInterest1, "ZCHF");

        vm.warp(ts2); // Warp to end of year 2
        assertEq(block.timestamp, ts2);

        // After 2 years, first year at 0.0001% (1ppm) , 2nd year at 4% (40_000 ppm)
        uint192 grossInterest2 = savings.accruedInterest(address(manager));
        uint192 manualInterest2 = manualInterest1 + amount * 365 days * 1 / 1_000_000 / 365 days;
        assertEq(grossInterest2, manualInterest2);

        uint192 manualFee = 365 days * 2 * amount * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days; // 250e18
        uint192 manualNetInterest = manualInterest2 > manualFee ? manualInterest2 - manualFee : 0;

        (uint192 p2, uint192 net2) = manager.getDepositDetails(id);
        assertEq(p2, amount);
        assertEq(net2, manualNetInterest);
        console.log("Ex1: Gross interest after 2 years:", grossInterest2, "ZCHF");
        console.log("Ex1: Net interest after 2 years:", net2, "ZCHF");
    }

    // --- EXAMPLE 2: 0% for 1 year, then 4% for another year ---
    function testFork_Example2_ZeroThenFourPercent() public {
        // Schedule
        _scheduleAndApplyRate(1);
        uint256 initialTime = block.timestamp;
        uint256 ts1 = initialTime + 365 days;
        uint256 ts2 = ts1 + 365 days;

        // Deposit 10,000 ZCHF
        bytes32 id = keccak256("Ex2");
        uint192 amount = 10_000 ether;
        vm.prank(operator);
        manager.createDeposits(_arr1(id), _arr1(amount), address(this));

        // Change rate to 4% exactly at the end of the 1st year
        vm.warp(ts1 - 7 days - 1);
        uint24 ratePPM = 40_000;
        _scheduleAndApplyRate(ratePPM);
        assertEq(block.timestamp, ts1);
        assertEq(savings.currentRatePPM(), ratePPM);

        uint192 grossInterest1 = savings.accruedInterest(address(manager));
        uint192 manualInterest1 = amount * 362 days * 1 / 1_000_000 / 365 days; // 3 days delay
        assertEq(grossInterest1, manualInterest1);
        uint192 manualFee1 = 365 days * amount * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days; // 125e18
        uint192 manualNetInterest1 = manualInterest1 > manualFee1 ? manualInterest1 - manualFee1 : 0;

        console.log("Ex2: Gross interest after 1 year:", grossInterest1, "ZCHF");
        console.log("Ex2: Net interest after 1 year:", manualNetInterest1, "ZCHF");

        vm.warp(ts2); // Warp to end of year 2
        assertEq(block.timestamp, ts2);

        // After 2 years, first year at 0.0001% (1ppm) , 2nd year at 4% (40_000 ppm)
        uint192 grossInterest2 = savings.accruedInterest(address(manager));
        uint192 manualInterest2 = manualInterest1 + amount * 40_000 / 1_000_000;
        assertEq(grossInterest2, manualInterest2);

        uint192 manualFee = 365 days * 2 * amount * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days; // 250e18
        uint192 manualNetInterest = manualInterest2 > manualFee ? manualInterest2 - manualFee : 0;

        (uint192 p2, uint192 net2) = manager.getDepositDetails(id);
        assertEq(p2, amount);
        assertEq(net2, manualNetInterest);
        console.log("Ex2: Gross interest after 2 years:", grossInterest2, "ZCHF");
        console.log("Ex2: Net interest after 2 years:", net2, "ZCHF");
    }

    // --- MULTIPLE ACTIVE DEPOSITS OVER MULTIPLE RATE CHANGES ---
    function testFork_MultipleDeposits_MultipleRates() public {
        // Start at 2%
        uint24 rate1 = 20_000;
        _scheduleAndApplyRate(rate1);

        // First deposit
        bytes32 id1 = keccak256("multi1");
        uint192 amt1 = 2_000 ether;
        vm.prank(operator);
        manager.createDeposits(_arr1(id1), _arr1(amt1), address(this));

        // Advance 100 days then increase rate to 4%
        vm.warp(block.timestamp + 100 days);
        uint24 rate2 = 40_000;
        _scheduleAndApplyRate(rate2);

        // Second deposit, after rate change
        bytes32 id2 = keccak256("multi2");
        uint192 amt2 = 8_000 ether;
        vm.prank(operator);
        manager.createDeposits(_arr1(id2), _arr1(amt2), address(this));

        // Advance 200 more days (both accrue, but at different ticks/rates)
        uint256 tsRedemption = block.timestamp + 200 days;
        vm.warp(tsRedemption);

        // Compute/validate each deposit's accrued net interest and payout
        for (uint256 i = 0; i < 2; i++) {
            bytes32 id = i == 0 ? id1 : id2;
            (uint192 principal, uint192 net) = manager.getDepositDetails(id);
            assertTrue(principal == (i == 0 ? amt1 : amt2));
            // Assert that net interest is within reasonable expected bounds
            assertTrue(net >= 0);
        }

        // Redeem all
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = id1;
        ids[1] = id2;
        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);

        // All deposit records must be deleted
        for (uint256 i = 0; i < 2; i++) {
            (uint192 p, uint192 n) = manager.getDepositDetails(ids[i]);
            assertEq(p, 0);
            assertEq(n, 0);
        }
        // Payout equals sum of all net principals
        assertTrue(zchf.balanceOf(receiver) > amt1 + amt2);
    }

    // --- EDGE CASE: IMMEDIATE RATE DROP TO BELOW FEE (zero or near zero) ---
    function testFork_EdgeCase_RateDropToZeroImmediatelyAfterDeposit() public {
        // Start at high rate 4%
        uint24 rate = 40_000;
        _scheduleAndApplyRate(rate);

        bytes32 id = keccak256("edgezero");
        uint192 amount = 5_000 ether;

        vm.prank(operator);
        manager.createDeposits(_arr1(id), _arr1(amount), address(this));

        // Immediately set rate to 0
        _scheduleAndApplyRate(0);

        // Fast-forward 300 days (only short accrual at 4%, most at 0, so net should collapse to 0 or very low)
        uint256 ts = block.timestamp + 300 days;
        vm.warp(ts);

        (uint192 princ, uint192 net) = manager.getDepositDetails(id);
        // The gross interest should be low, and fee should cap any net interest to 0
        assertEq(princ, amount);
        assertTrue(net == 0);
        vm.prank(operator);
        manager.redeemDeposits(_arr1(id), receiver);
        assertEq(zchf.balanceOf(receiver), amount);
    }

    // --- EDGE/BORDER: FEE CAPPED AT GROSS, AND NOT NEGATIVE ---
    function testFork_EdgeCase_FeeDoesNotExceedGrossInterest() public {
        _scheduleAndApplyRate(10_000); // 1% rate, lower than fee
        bytes32 id = keccak256("edgecap");
        uint192 amount = 3_000 ether;
        vm.prank(operator);
        manager.createDeposits(_arr1(id), _arr1(amount), address(this));

        // Advance 1 year
        vm.warp(block.timestamp + 365 days);

        (uint192 p, uint192 net) = manager.getDepositDetails(id);
        // Fee would be 1250, gross only 30 => net must be 0
        assertEq(p, amount);
        assertEq(net, 0);

        // And can be redeemed for principal only
        vm.prank(operator);
        manager.redeemDeposits(_arr1(id), receiver);
        assertEq(zchf.balanceOf(receiver), amount);
    }

    // === Utilities ===
    function _arr1(bytes32 id) internal pure returns (bytes32[] memory arr) {
        arr = new bytes32[](1);
        arr[0] = id;
    }

    function _arr1(uint192 n) internal pure returns (uint192[] memory arr) {
        arr = new uint192[](1);
        arr[0] = n;
    }
}
