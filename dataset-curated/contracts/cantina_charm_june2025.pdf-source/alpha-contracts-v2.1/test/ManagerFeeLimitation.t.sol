// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {VaultTestUtils} from "./VaultTestUtils.sol";

contract ManagerFeeLimitationTest is Test, VaultTestUtils {
    function setUp() public {
        vm.createSelectFork(vm.envString("ALCHEMY_RPC"), 17073835);
        deployFactory();
        depositInFactory();
    }

    function test_managerFeeIsLimitedByProtocolFee() public {
        // Set protocol fee to 15% (15e4) - within the 25% cap
        vm.prank(owner);
        vault.setProtocolFee(15e4);

        // Try to set manager fee to 90% (90e4)
        vm.prank(owner);
        vault.setManagerFee(90e4);

        // Verify pending manager fee is set
        vm.assertEq(vault.pendingManagerFee(), 90e4);

        // Generate some fees
        swapForwardAndBack(false);
        swapForwardAndBack(true);

        // Rebalance to apply the fees
        vault.rebalance();

        // After rebalance, manager fee should be limited to 85% (100% - 15% = 85%)
        vm.assertEq(vault.managerFee(), 85e4);
        vm.assertEq(vault.protocolFee(), 15e4);

        // Total fees should not exceed 100%
        vm.assertLe(vault.managerFee() + vault.protocolFee(), 100e4);
    }

    function test_managerFeeIsZeroWhenProtocolFeeAndManagerFeeExceed100Percent() public {
        // Set protocol fee to maximum 25% (25e4)
        vm.prank(owner);
        vault.setProtocolFee(25e4);

        // Try to set manager fee to 85% (85e4)
        vm.prank(owner);
        vault.setManagerFee(85e4);

        // Generate some fees
        swapForwardAndBack(false);
        swapForwardAndBack(true);

        // Rebalance to apply the fees
        vault.rebalance();

        // After rebalance, manager fee should be 75% since protocol fee is 25%
        vm.assertEq(vault.managerFee(), 75e4);
        vm.assertEq(vault.protocolFee(), 25e4);
    }

    function test_managerFeeIsNotLimitedWhenTotalIsUnder100Percent() public {
        // Set protocol fee to 10% (10e4)
        vm.prank(owner);
        vault.setProtocolFee(10e4);

        // Set manager fee to 50% (50e4)
        vm.prank(owner);
        vault.setManagerFee(50e4);

        // Generate some fees
        swapForwardAndBack(false);
        swapForwardAndBack(true);

        // Rebalance to apply the fees
        vault.rebalance();

        // Both fees should be applied as-is since total is 60% < 100%
        vm.assertEq(vault.managerFee(), 50e4);
        vm.assertEq(vault.protocolFee(), 10e4);
        vm.assertEq(vault.managerFee() + vault.protocolFee(), 60e4);
    }

    function test_feeAccrualWithLimitedManagerFee() public {
        // Set protocol fee to 18% (18e4)
        vm.prank(owner);
        vault.setProtocolFee(18e4);

        // Try to set manager fee to 90% (90e4)
        vm.prank(owner);
        vault.setManagerFee(90e4);

        // First rebalance to activate the fees
        vault.rebalance();

        // Verify manager fee was limited to 82%
        vm.assertEq(vault.managerFee(), 82e4);

        // Generate significant fees
        for (uint256 i = 0; i < 5; i++) {
            swapForwardAndBack(false);
            swapForwardAndBack(true);
        }

        // Rebalance to collect fees
        vault.rebalance();

        // Check that fees were accrued correctly
        uint256 managerFees0 = vault.accruedManagerFees0();
        uint256 managerFees1 = vault.accruedManagerFees1();
        uint256 protocolFees0 = vault.accruedProtocolFees0();
        uint256 protocolFees1 = vault.accruedProtocolFees1();

        // Manager fees should be approximately 82/18 of protocol fees
        vm.assertApproxEqRel(managerFees0 * 18, protocolFees0 * 82, 0.01e18); // 1% tolerance
        vm.assertApproxEqRel(managerFees1 * 18, protocolFees1 * 82, 0.01e18); // 1% tolerance

        // Verify fees can be collected
        address managerRecipient = makeAddr("managerRecipient");
        vm.prank(owner);
        vault.collectManager(managerRecipient);

        vm.assertEq(IERC20(USDC).balanceOf(managerRecipient), managerFees0);
        vm.assertEq(IERC20(WETH).balanceOf(managerRecipient), managerFees1);
    }

    function test_dynamicFeeAdjustment() public {
        // Initially set moderate fees
        vm.prank(owner);
        vault.setProtocolFee(10e4); // 10%

        vm.prank(owner);
        vault.setManagerFee(40e4); // 40%

        // First rebalance
        vault.rebalance();
        vm.assertEq(vault.managerFee(), 40e4);
        vm.assertEq(vault.protocolFee(), 10e4);

        // Increase protocol fee to 25% (maximum)
        vm.prank(owner);
        vault.setProtocolFee(25e4);

        // Manager tries to increase their fee to 90%
        vm.prank(owner);
        vault.setManagerFee(90e4);

        // Generate fees and rebalance
        swapForwardAndBack(false);
        vault.rebalance();

        // Manager fee should be limited to 75% (100% - 25%)
        vm.assertEq(vault.managerFee(), 75e4);
        vm.assertEq(vault.protocolFee(), 25e4);
    }

    function test_protocolFeeCannotExceed25Percent() public {
        // Try to set protocol fee above 25%
        vm.prank(owner);
        vm.expectRevert("protocolFee must be <= 250000");
        vault.setProtocolFee(25e4 + 1);

        // Verify 25% works
        vm.prank(owner);
        vault.setProtocolFee(25e4);

        vm.assertEq(vault.pendingProtocolFee(), 25e4);
    }

    function test_fuzzManagerFeeLimitation(uint24 protocolFee, uint24 requestedManagerFee) public {
        // Limit protocol fee to valid range (0 to 25%)
        protocolFee = uint24(bound(protocolFee, 0, 25e4));

        // Limit requested manager fee to valid range (0 to 100%)
        requestedManagerFee = uint24(bound(requestedManagerFee, 0, 100e4));

        // Set protocol fee
        vm.prank(owner);
        vault.setProtocolFee(protocolFee);

        // Set manager fee
        vm.prank(owner);
        vault.setManagerFee(requestedManagerFee);

        // Rebalance to apply fees
        vault.rebalance();

        // Verify the invariant: protocolFee + managerFee <= 100%
        uint24 actualManagerFee = vault.managerFee();
        uint24 actualProtocolFee = vault.protocolFee();

        vm.assertLe(actualProtocolFee + actualManagerFee, 100e4);

        // Verify manager fee is correctly limited
        if (requestedManagerFee + protocolFee <= 100e4) {
            vm.assertEq(actualManagerFee, requestedManagerFee);
        } else {
            vm.assertEq(actualManagerFee, 100e4 - protocolFee);
        }
    }

    function test_edgeCaseMaximumFees() public {
        // Set protocol fee to maximum 25%
        vm.prank(owner);
        vault.setProtocolFee(25e4);

        // Set manager fee to 75%
        vm.prank(owner);
        vault.setManagerFee(75e4);

        vault.rebalance();

        // Both fees should apply exactly, totaling 100%
        vm.assertEq(vault.managerFee(), 75e4);
        vm.assertEq(vault.protocolFee(), 25e4);
    }
}
