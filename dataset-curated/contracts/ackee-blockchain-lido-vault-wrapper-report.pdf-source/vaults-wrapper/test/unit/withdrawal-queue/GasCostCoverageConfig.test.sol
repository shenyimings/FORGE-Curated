// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupWithdrawalQueue} from "./SetupWithdrawalQueue.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";

contract GasCostCoverageConfigTest is Test, SetupWithdrawalQueue {
    function setUp() public override {
        super.setUp();

        pool.depositETH{value: 1_000 ether}(address(this), address(0));
    }

    // Default value

    function test_GetFinalizationGasCostCoverage_DefaultZero() public view {
        assertEq(withdrawalQueue.getFinalizationGasCostCoverage(), 0);
    }

    // Setter

    function test_SetFinalizationGasCostCoverage_UpdatesValue() public {
        uint256 coverage = 0.0001 ether;

        vm.prank(finalizeRoleHolder);
        withdrawalQueue.setFinalizationGasCostCoverage(coverage);
        assertEq(withdrawalQueue.getFinalizationGasCostCoverage(), coverage);
    }

    function test_SetFinalizationGasCostCoverage_RevertAboveMax() public {
        uint256 coverage = withdrawalQueue.MAX_GAS_COST_COVERAGE() + 1;

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.GasCostCoverageTooLarge.selector, coverage));
        vm.prank(finalizeRoleHolder);
        withdrawalQueue.setFinalizationGasCostCoverage(coverage);
    }

    function test_SetFinalizationGasCostCoverage_MaxValueCanBeSet() public {
        uint256 coverage = withdrawalQueue.MAX_GAS_COST_COVERAGE();

        vm.prank(finalizeRoleHolder);
        withdrawalQueue.setFinalizationGasCostCoverage(coverage);
        assertEq(withdrawalQueue.getFinalizationGasCostCoverage(), coverage);
    }

    // Access control

    function test_SetFinalizationGasCostCoverage_CanBeCalledByFinalizeRole() public {
        vm.prank(finalizeRoleHolder);
        withdrawalQueue.setFinalizationGasCostCoverage(0.0001 ether);
    }

    function test_SetFinalizationGasCostCoverage_CantBeCalledStranger() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), withdrawalQueue.FINALIZE_ROLE()
            )
        );
        withdrawalQueue.setFinalizationGasCostCoverage(0.0001 ether);
    }
}
