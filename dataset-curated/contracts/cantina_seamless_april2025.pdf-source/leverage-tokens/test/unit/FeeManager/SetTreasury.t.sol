// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

// Internal imports
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {IFeeManager} from "src/interfaces/IFeeManager.sol";
import {ExternalAction} from "src/types/DataTypes.sol";
import {FeeManagerTest} from "test/unit/FeeManager/FeeManager.t.sol";

contract SetTreasuryTest is FeeManagerTest {
    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setTreasury(address treasury) public {
        vm.expectEmit(true, true, true, true);
        emit IFeeManager.TreasurySet(treasury);

        _setTreasury(feeManagerRole, treasury);
        assertEq(feeManager.getTreasury(), treasury);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setTreasury_RevertIf_CallerIsNotFeeManagerRole(address caller, address treasury) public {
        vm.assume(caller != feeManagerRole);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, feeManager.FEE_MANAGER_ROLE()
            )
        );
        _setTreasury(caller, treasury);
    }

    function test_setTreasury_ZeroAddressResetsTreasuryFees() public {
        _setTreasury(feeManagerRole, makeAddr("treasury"));
        _setTreasuryActionFee(feeManagerRole, ExternalAction.Deposit, 100);
        _setTreasuryActionFee(feeManagerRole, ExternalAction.Withdraw, 100);

        _setTreasury(feeManagerRole, address(0));
        assertEq(feeManager.getTreasuryActionFee(ExternalAction.Deposit), 0);
        assertEq(feeManager.getTreasuryActionFee(ExternalAction.Withdraw), 0);
    }
}
