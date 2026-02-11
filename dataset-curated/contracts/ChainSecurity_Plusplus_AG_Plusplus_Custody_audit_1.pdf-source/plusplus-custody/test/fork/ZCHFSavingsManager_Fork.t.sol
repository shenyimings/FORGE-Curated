// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ZCHFSavingsManager} from "src/ZCHFSavingsManager.sol";
// Import the error interface used for custom revert expectations
import {IZCHFErrors} from "../interfaces/IZCHFErrors.sol";
// Import the savings interface from the test folder. This interface matches
// the live module.
import {IFrankencoinSavings} from "../interfaces/IFrankencoinSavings.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/// @title ZCHFSavingsManagerForkTest
/// @notice Integration tests for ZCHFSavingsManager using a mainnet fork. These
/// tests interact with the live ZCHF token and savings module deployed on
/// Ethereum mainnet. They verify that the manager computes interest and
/// fees identically to on-chain values and that revert paths are enforced
/// via the custom error interface.
contract ZCHFSavingsManagerForkTest is Test {
    // Live contract addresses on Ethereum mainnet
    address constant ZCHF_ADDRESS = 0xB58E61C3098d85632Df34EecfB899A1Ed80921cB;
    address constant SAVINGS_MODULE = 0x27d9AD987BdE08a0d083ef7e0e4043C857A17B38;
    address constant WHALE = 0xa8c4E40075D1bb3A6E3343Be55b32B8E4a5612a1;

    ZCHFSavingsManager internal manager;
    // Minimal ERC20 interface for interacting with the live ZCHF token. We
    // declare it here to avoid relying on external packages in tests.

    IERC20 internal zchf;
    IFrankencoinSavings internal savings;

    address internal admin;
    address internal operator;
    address internal receiver;

    // Redeclare events from the manager for expectEmit. These must match
    // exactly the definitions in ZCHFSavingsManager.
    event DepositCreated(bytes32 indexed identifier, uint192 amount);
    event DepositRedeemed(bytes32 indexed identifier, uint192 totalAmount);

    /// @notice Forks mainnet and deploys a fresh manager connected to the live
    /// savings module and token. The fork URL must be defined in .env via
    /// MAINNET_RPC_URL. The whale address is impersonated to supply ZCHF
    /// tokens for the tests.
    function setUp() public {
        // Create and select the mainnet fork
        uint256 forkId = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(forkId);

        admin = address(this);
        operator = address(this);
        receiver = makeAddr("receiver");

        // Bind to the live contracts
        zchf = IERC20(ZCHF_ADDRESS);
        savings = IFrankencoinSavings(SAVINGS_MODULE);

        // Deploy a new savings manager that points at the live modules
        manager = new ZCHFSavingsManager(admin, ZCHF_ADDRESS, SAVINGS_MODULE);

        // Grant operator and receiver roles to the appropriate addresses and set limit
        manager.grantRole(manager.OPERATOR_ROLE(), operator);
        manager.grantRole(manager.RECEIVER_ROLE(), receiver);
        manager.setDailyLimit(operator, 1_000_000e18);

        // Impersonate the whale to obtain ZCHF for deposits
        uint256 supply = 10_000 ether;
        vm.startPrank(WHALE);
        require(zchf.transfer(address(this), supply), "transfer failed");
        vm.stopPrank();

        // Approve the manager to pull unlimited ZCHF from this contract
        zchf.approve(address(manager), type(uint256).max);
        // Provide this contract with ETH so that on-chain calls succeed
        vm.deal(address(this), 10 ether);
    }

    /// @notice Tests that creating a deposit stores the correct ticksAtDeposit
    /// computed from the live savings module. The expected value is
    /// savings.ticks(now) + savings.currentRatePPM() * savings.INTEREST_DELAY().
    function testFork_CreateDeposit_StoresCorrectTicks() public {
        bytes32 id = keccak256("forkTicks");
        uint192 amount = 100 ether;
        // Capture base values before deposit
        uint64 baseTicks = savings.ticks(block.timestamp);
        uint24 rate = savings.currentRatePPM();
        uint64 delay = savings.INTEREST_DELAY();
        uint64 expectedTicksAtDeposit = baseTicks + uint64(uint256(rate) * uint256(delay));

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id;
        uint192[] memory amounts = new uint192[](1);
        amounts[0] = amount;
        // Create the deposit
        vm.prank(operator);
        manager.createDeposits(ids, amounts, address(this));

        // Retrieve the stored deposit and check ticksAtDeposit matches
        (,, uint64 storedTicks) = manager.deposits(id);
        assertEq(storedTicks, expectedTicksAtDeposit);
    }

    /// @notice Tests redeeming a deposit after a period of time on the mainnet
    /// fork. The actual transfer to the receiver should equal the initial
    /// amount plus the net interest computed off-chain. The deposit should
    /// be removed and an event emitted. This test also demonstrates the
    /// pattern for expecting a custom error revert using IZCHFErrors.
    function testFork_DepositAndRedeem() public {
        // Set up a deposit of 500 ZCHF
        bytes32 id = keccak256("forkRedeem");
        uint192 amount = 500 ether;
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id;
        amounts[0] = amount;

        // Create the deposit
        vm.prank(operator);
        manager.createDeposits(ids, amounts, address(this));

        // Snapshot deposit metadata
        (uint192 initial, uint40 createdAt, uint64 ticksAtDeposit) = manager.deposits(id);

        // Advance time by seven days
        uint256 futureTs = createdAt + 7 days;
        vm.warp(futureTs);

        // Compute expected amounts using live savings data
        uint64 currentTicks = savings.ticks(futureTs);
        uint64 deltaTicks = currentTicks > ticksAtDeposit ? currentTicks - ticksAtDeposit : 0;
        uint256 totalInterest = uint256(deltaTicks) * initial / 1_000_000 / 365 days;
        uint256 feeableTicks = (futureTs - createdAt) * manager.FEE_ANNUAL_PPM();
        uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;
        uint256 fee = feeTicks * initial / 1_000_000 / 365 days;
        uint256 expectedNet = totalInterest > fee ? totalInterest - fee : 0;
        uint192 expectedTotal = uint192(initial + expectedNet);

        // Expect the DepositRedeemed event
        vm.expectEmit(true, false, false, true);
        emit ZCHFSavingsManager.DepositRedeemed(id, expectedTotal);

        // Redeem the deposit
        bytes32[] memory idList = new bytes32[](1);
        idList[0] = id;
        vm.prank(operator);
        manager.redeemDeposits(idList, receiver);

        // Verify receiver balance
        assertEq(zchf.balanceOf(receiver), expectedTotal);
        // Ensure deposit is cleared
        (uint192 postPrincipal, uint192 postNet) = manager.getDepositDetails(id);
        assertEq(postPrincipal, 0);
        assertEq(postNet, 0);
    }

    /// @notice Demonstrates expecting a custom error revert on the fork. When
    /// redeeming with an address lacking the RECEIVER_ROLE, the call should
    /// revert with InvalidReceiver. The expected revert data is encoded
    /// using the selector from IZCHFErrors.
    function testFork_RedeemReverts_InvalidReceiver() public {
        // Create a deposit to redeem
        bytes32 id = keccak256("forkInvalidReceiver");
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id;
        uint192[] memory amounts = new uint192[](1);
        amounts[0] = 100 ether;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, address(this));

        // Use an address without the RECEIVER_ROLE
        address invalidReceiver = makeAddr("notReceiver");
        // Expect revert with encoded selector and argument
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.InvalidReceiver.selector, invalidReceiver));
        manager.redeemDeposits(ids, invalidReceiver);
    }

    /// @notice Creates a deposit, advances time by 2 days (still in lockout), then 5 more days,
    /// and confirms no interest before lock ends and positive interest after. Also checks
    /// off-chain fee and net interest math matches on-chain result.
    function testFork_InterestLockoutAndAccrualCheck() public {
        bytes32 id = keccak256("forkDelayAccrual");
        uint192 amount = 1000 ether;
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id;
        amounts[0] = amount;

        vm.prank(operator);
        manager.createDeposits(ids, amounts, address(this));

        (uint192 initial, uint40 createdAt, uint64 ticksAtDeposit) = manager.deposits(id);
        assertEq(initial, amount);

        // Advance to 2 days after deposit (within lockout)
        vm.warp(createdAt + 2 days);
        (, uint192 netInterestAfter2d) = manager.getDepositDetails(id);
        assertEq(netInterestAfter2d, 0, "Interest should be zero within 3-day lockout");

        // Advance to 7 days after deposit (4 days of accrual after lockout ends)
        vm.warp(createdAt + 7 days);
        (, uint192 netInterestAfter7d) = manager.getDepositDetails(id);
        assertGt(netInterestAfter7d, 0, "Interest should be positive after 3-day lockout");

        // Compute expected interest and fee manually
        uint64 ticksNow = savings.ticks(block.timestamp);
        uint64 deltaTicks = ticksNow > ticksAtDeposit ? ticksNow - ticksAtDeposit : 0;
        uint256 totalInterest = uint256(deltaTicks) * amount / 1_000_000 / 365 days;

        uint256 duration = block.timestamp - createdAt;
        uint256 feeableTicks = duration * manager.FEE_ANNUAL_PPM();
        uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;
        uint256 fee = feeTicks * amount / 1_000_000 / 365 days;

        uint256 expectedNetInterest = totalInterest > fee ? totalInterest - fee : 0;

        assertEq(uint256(netInterestAfter7d), expectedNetInterest, "Net interest mismatch");
    }
}
