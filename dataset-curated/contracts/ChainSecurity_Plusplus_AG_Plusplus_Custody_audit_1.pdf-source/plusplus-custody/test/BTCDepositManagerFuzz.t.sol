// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/StdCheats.sol";
import "forge-std/StdAssertions.sol";

import {WBTCDepositManager} from "src/WBTCDepositManager.sol";
import {MockERC20} from "test/utils/MockERC20.sol";

/// @title WBTCDepositManagerFuzzTest
/// @notice Property‑based tests for deposit value decay and monotonicity.
contract WBTCDepositManagerFuzzTest is Test {
    WBTCDepositManager internal manager;
    MockERC20 internal token;
    address internal admin = makeAddr("0xA11CE");
    address internal operator = makeAddr("0x0P3R8"); // test operator address
    address internal receiver = makeAddr("0xBEEF"); // account used for redemption and fee collection

    function setUp() public {
        token = new MockERC20("Mock WBTC", "mWBTC", 8);
        manager = new WBTCDepositManager(admin, address(token));
        vm.startPrank(admin);
        manager.grantRole(manager.OPERATOR_ROLE(), operator);
        manager.grantRole(manager.RECEIVER_ROLE(), receiver);
        manager.setDailyLimit(operator, 1_000_000e8);
        vm.stopPrank();
        // Provide operator with large balance and approve manager
        token.mint(operator, type(uint128).max);
        vm.prank(operator);
        token.approve(address(manager), type(uint256).max);
    }

    /// @notice depositValue should approximate the mathematical formula for any amount and duration
    function testDepositValueMatchesFormula(uint192 amountRaw, uint256 durationRaw) public {
        // Bound the amount between 1 and 1e15 (well below uint192 max, ensures safe multiplication)
        uint192 amount = uint192(bound(uint256(amountRaw), 1, 1e15));
        // Bound duration up to 20 years
        uint256 duration = bound(durationRaw, 0, 20 * 365 days);

        // Use a unique identifier per test
        bytes32 id = keccak256(abi.encode(amount, duration));
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id;
        amounts[0] = amount;
        // Create the deposit
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);

        // Warp by duration
        vm.warp(block.timestamp + duration);

        // Compute expected value using the same integer maths
        uint256 decay = (duration * uint256(amount)) * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days;
        uint256 expected = uint256(amount) > decay ? uint256(amount) - decay : 0;
        uint256 actual = manager.depositValue(id);

        // The difference should be no more than 1 unit due to integer rounding
        assertApproxEqAbs(actual, expected, 1);
    }

    /// @notice depositValue should be non‑increasing in time
    function testDepositValueMonotonic(uint192 amountRaw, uint256 dt1Raw, uint256 dt2Raw) public {
        uint192 amount = uint192(bound(uint256(amountRaw), 1, 1e12));
        // dt1 between 1 hour and 5 years
        uint256 dt1 = bound(dt1Raw, 1 hours, 5 * 365 days);
        // dt2 between dt1 and dt1 + 5 years
        uint256 dt2 = bound(dt2Raw, dt1, dt1 + 5 * 365 days);
        bytes32 id = keccak256(abi.encode(amount, dt1, dt2));
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id;
        amounts[0] = amount;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);
        // Evaluate at dt1
        vm.warp(block.timestamp + dt1);
        uint256 value1 = manager.depositValue(id);
        // Warp further to dt2
        vm.warp(block.timestamp + (dt2 - dt1));
        uint256 value2 = manager.depositValue(id);
        // value2 should be less than or equal to value1
        assertLe(value2, value1, "deposit value should not increase over time");
    }

    /// @notice depositValue should return zero after an extremely long time relative to principal
    function testDepositValueEventuallyZeroFuzz(uint192 amountRaw, uint256 yearsRaw) public {
        uint192 amount = uint192(bound(uint256(amountRaw), 1, 1e6));
        // Bound years between 110 and 1000 to ensure a long period
        uint256 yearsForward = bound(yearsRaw, 110, 1000);
        bytes32 id = keccak256(abi.encode(amount, yearsForward));
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id;
        amounts[0] = amount;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, operator);
        vm.warp(block.timestamp + yearsForward * 365 days);
        assertEq(manager.depositValue(id), 0, "deposit should fully decay after very long time");
    }

    /// @notice Creates 5–100 deposits at staggered timestamps and validates their decayed values
    function testFuzz_MultipleDepositsValueConsistency(uint256 seed) public {
        uint256 num = bound(seed % 100, 5, 100);
        bytes32[] memory ids = new bytes32[](num);
        uint192[] memory amounts = new uint192[](num);
        uint256[] memory startTimes = new uint256[](num);
        vm.warp(1_700_000_000);
        uint256 now_ = block.timestamp;
        uint256 t0 = now_;

        // Simulate staggered deposit timestamps (random time between deposits)
        for (uint256 i = 0; i < num; ++i) {
            uint192 amount = uint192(bound(uint256(keccak256(abi.encode(seed, i, "amount"))), 1, 1e12));
            uint256 offset = bound(uint256(keccak256(abi.encode(seed, i, "offset"))), 1 minutes, 10 days);
            t0 = t0 + offset;

            bytes32 id = keccak256(abi.encodePacked(seed, i, amount, t0));
            ids[i] = id;
            amounts[i] = amount;
            startTimes[i] = t0;

            // Warp forward
            vm.warp(t0);

            vm.prank(operator);
            bytes32[] memory aids = new bytes32[](1);
            uint192[] memory aamounts = new uint192[](1);
            aids[0] = id;
            aamounts[0] = amount;
            manager.createDeposits(aids, aamounts, operator);
        }

        // Warp forward to common evaluation time
        vm.warp(now_);

        // Validate values
        for (uint256 i = 0; i < num; ++i) {
            uint192 principal = amounts[i];
            uint256 elapsed = now_ - startTimes[i];
            uint256 decay = (elapsed * uint256(principal)) * manager.FEE_ANNUAL_PPM() / 1_000_000 / 365 days;
            uint256 expected = principal > decay ? principal - decay : 0;
            uint256 actual = manager.depositValue(ids[i]);
            assertApproxEqAbs(actual, expected, 1);
        }
    }

    // -- helpers --
    function toBytes(bytes32[] memory inArr) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](inArr.length);
        for (uint256 i = 0; i < inArr.length; ++i) {
            out[i] = inArr[i];
        }
    }

    function toUint192(uint192[] memory inArr) internal pure returns (uint192[] memory out) {
        out = new uint192[](inArr.length);
        for (uint256 i = 0; i < inArr.length; ++i) {
            out[i] = inArr[i];
        }
    }
}
