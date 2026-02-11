// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ZCHFSavingsManager} from "src/ZCHFSavingsManager.sol";
import {IZCHFErrors} from "../interfaces/IZCHFErrors.sol";
import {IFrankencoinSavings} from "../interfaces/IFrankencoinSavings.sol";

// Minimal ERC20 interface declaration
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/// @title ZCHFSavingsManagerForkMultiTest
/// @notice Additional integration and fuzz tests executed against a mainnet
/// fork. These tests exercise multiple deposit and redemption scenarios,
/// including batch operations and randomized inputs, to ensure that the
/// savings manager behaves consistently under varied conditions.
contract ZCHFSavingsManagerForkMultiTest is Test {
    // Mainnet contract addresses and whale for acquiring ZCHF
    address constant ZCHF_ADDRESS = 0xB58E61C3098d85632Df34EecfB899A1Ed80921cB;
    address constant SAVINGS_MODULE = 0x27d9AD987BdE08a0d083ef7e0e4043C857A17B38;
    address constant WHALE = 0xa8c4E40075D1bb3A6E3343Be55b32B8E4a5612a1;

    ZCHFSavingsManager internal manager;
    IERC20 internal zchf;
    IFrankencoinSavings internal savings;

    address internal admin;
    address internal operator;
    address internal receiver;

    // Redeclare events for expectEmit
    event DepositCreated(bytes32 indexed identifier, uint192 amount);
    event DepositRedeemed(bytes32 indexed identifier, uint192 totalAmount);

    /// @notice Sets up the fork, deploys a new manager and funds it with ZCHF.
    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(forkId);

        admin = address(this);
        operator = address(this);
        receiver = makeAddr("receiverMulti");

        zchf = IERC20(ZCHF_ADDRESS);
        savings = IFrankencoinSavings(SAVINGS_MODULE);
        manager = new ZCHFSavingsManager(admin, ZCHF_ADDRESS, SAVINGS_MODULE);
        manager.grantRole(manager.OPERATOR_ROLE(), operator);
        manager.grantRole(manager.RECEIVER_ROLE(), receiver);
        manager.setDailyLimit(operator, 1_000_000e18);

        // Impersonate whale to acquire ample ZCHF for deposits
        uint256 supply = 50_000 ether;
        vm.startPrank(WHALE);
        require(zchf.transfer(address(this), supply), "transfer failed");
        vm.stopPrank();

        // Approve manager
        zchf.approve(address(manager), type(uint256).max);
        vm.deal(address(this), 20 ether);
    }

    /// @notice Creates three deposits in a single call and later redeems them
    /// in one batch. Ensures that the aggregated redemption equals the sum
    /// of each deposit's principal and net interest computed off-chain.
    function testFork_MultipleDepositsBatchRedeem() public {
        // Prepare identifiers and amounts
        bytes32[] memory ids = new bytes32[](3);
        uint192[] memory amounts = new uint192[](3);
        ids[0] = keccak256("batch1");
        ids[1] = keccak256("batch2");
        ids[2] = keccak256("batch3");
        amounts[0] = 300 ether;
        amounts[1] = 500 ether;
        amounts[2] = 700 ether;

        // Create all deposits at once
        vm.prank(operator);
        manager.createDeposits(ids, amounts, address(this));

        // Snapshot deposit metadata for each id
        uint192[3] memory initial;
        uint40[3] memory createdAt;
        uint64[3] memory ticksAtDeposit;
        for (uint256 i = 0; i < 3; i++) {
            (uint192 init, uint40 ts, uint64 tick) = manager.deposits(ids[i]);
            initial[i] = init;
            createdAt[i] = ts;
            ticksAtDeposit[i] = tick;
        }

        // Advance time by 12 days
        uint256 futureTs = block.timestamp + 12 days;
        vm.warp(futureTs);

        // Compute expected totals for each deposit
        uint192 totalExpected;
        for (uint256 i = 0; i < 3; i++) {
            uint64 currentTicks = savings.ticks(futureTs);
            uint64 deltaTicks = currentTicks > ticksAtDeposit[i] ? currentTicks - ticksAtDeposit[i] : 0;
            uint256 totalInterest = uint256(deltaTicks) * initial[i] / 1_000_000 / 365 days;
            uint256 duration = futureTs - createdAt[i];
            uint256 feeableTicks = duration * manager.FEE_ANNUAL_PPM();
            uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;
            uint256 fee = feeTicks * initial[i] / 1_000_000 / 365 days;
            uint256 net = totalInterest > fee ? totalInterest - fee : 0;
            totalExpected += uint192(initial[i] + net);
        }

        // Expect three DepositRedeemed events
        for (uint256 i = 0; i < 3; i++) {
            // Compute per-deposit total for event expectation
            uint64 currentTicks = savings.ticks(futureTs);
            uint64 deltaTicks = currentTicks > ticksAtDeposit[i] ? currentTicks - ticksAtDeposit[i] : 0;
            uint256 totalInterest = uint256(deltaTicks) * initial[i] / 1_000_000 / 365 days;
            uint256 duration = futureTs - createdAt[i];
            uint256 feeableTicks = duration * manager.FEE_ANNUAL_PPM();
            uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;
            uint256 fee = feeTicks * initial[i] / 1_000_000 / 365 days;
            uint256 net = totalInterest > fee ? totalInterest - fee : 0;
            uint192 total = uint192(initial[i] + net);
            vm.expectEmit(true, false, false, true);
            emit DepositRedeemed(ids[i], total);
        }

        // Redeem all in one call
        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);

        // Verify receiver balance equals the aggregated total
        assertEq(zchf.balanceOf(receiver), totalExpected);
        // Ensure all deposits are cleared
        for (uint256 i = 0; i < 3; i++) {
            (uint192 p, uint192 n) = manager.getDepositDetails(ids[i]);
            assertEq(p, 0);
            assertEq(n, 0);
        }
    }

    /// @notice Fuzz test combining two deposits created at different times and
    /// redeemed together. Randomized amounts and durations are used to
    /// exercise the interest and fee logic under varied conditions.
    function testFuzz_MultipleDepositsRedeem(uint192 amount1, uint192 amount2, uint32 gap, uint32 duration) public {
        // Constrain values to avoid overflows and meaningless inputs
        vm.assume(amount1 > 0 && amount1 <= 1_000 ether);
        vm.assume(amount2 > 0 && amount2 <= 1_000 ether);
        // gap is the time between the two deposit operations (max 2 days)
        vm.assume(gap <= 2 days);
        // duration after the last deposit before redemption (max 20 days)
        vm.assume(duration > 0 && duration <= 20 days);

        // Prepare ids
        bytes32 id1 = keccak256(abi.encodePacked("fuzz1", amount1, gap, duration));
        bytes32 id2 = keccak256(abi.encodePacked("fuzz2", amount2, gap, duration));

        // First deposit
        {
            bytes32[] memory idsF = new bytes32[](1);
            uint192[] memory amtsF = new uint192[](1);
            idsF[0] = id1;
            amtsF[0] = amount1;
            vm.prank(operator);
            manager.createDeposits(idsF, amtsF, address(this));
        }
        // Advance by gap seconds before second deposit
        vm.warp(block.timestamp + gap);

        // Second deposit
        {
            bytes32[] memory idsF2 = new bytes32[](1);
            uint192[] memory amtsF2 = new uint192[](1);
            idsF2[0] = id2;
            amtsF2[0] = amount2;
            vm.prank(operator);
            manager.createDeposits(idsF2, amtsF2, address(this));
        }

        // Snapshot metadata
        (uint192 init1, uint40 ts1, uint64 ticks1) = manager.deposits(id1);
        (uint192 init2, uint40 ts2, uint64 ticks2) = manager.deposits(id2);

        // Advance time by duration from the second deposit timestamp
        uint256 futureTs = uint256(ts2) + duration;
        vm.warp(futureTs);

        // Compute expected totals individually
        uint192 totalExpected;
        {
            // deposit 1
            uint64 currentTicks = savings.ticks(futureTs);
            uint64 deltaTicks = currentTicks > ticks1 ? currentTicks - ticks1 : 0;
            uint256 totalInterest = uint256(deltaTicks) * init1 / 1_000_000 / 365 days;
            uint256 feeableTicks = (futureTs - ts1) * manager.FEE_ANNUAL_PPM();
            uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;
            uint256 fee = feeTicks * init1 / 1_000_000 / 365 days;
            uint256 net = totalInterest > fee ? totalInterest - fee : 0;
            totalExpected += uint192(init1 + net);
        }
        {
            // deposit 2
            uint64 currentTicks = savings.ticks(futureTs);
            uint64 deltaTicks = currentTicks > ticks2 ? currentTicks - ticks2 : 0;
            uint256 totalInterest = uint256(deltaTicks) * init2 / 1_000_000 / 365 days;
            uint256 feeableTicks = (futureTs - ts2) * manager.FEE_ANNUAL_PPM();
            uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;
            uint256 fee = feeTicks * init2 / 1_000_000 / 365 days;
            uint256 net = totalInterest > fee ? totalInterest - fee : 0;
            totalExpected += uint192(init2 + net);
        }

        // Redeem both deposits at once
        bytes32[] memory allIds = new bytes32[](2);
        allIds[0] = id1;
        allIds[1] = id2;
        vm.prank(operator);
        manager.redeemDeposits(allIds, receiver);

        // Validate aggregated payout
        assertEq(zchf.balanceOf(receiver), totalExpected, "redeem payout mismatch");
        // Ensure deposits cleared
        (uint192 p1, uint192 n1) = manager.getDepositDetails(id1);
        (uint192 p2, uint192 n2) = manager.getDepositDetails(id2);
        assertEq(p1, 0);
        assertEq(n1, 0);
        assertEq(p2, 0);
        assertEq(n2, 0);
    }
}
