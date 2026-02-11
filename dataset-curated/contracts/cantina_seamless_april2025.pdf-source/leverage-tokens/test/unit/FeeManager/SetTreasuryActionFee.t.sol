// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

// Internal imports
import {IFeeManager} from "src/interfaces/IFeeManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {ExternalAction} from "src/types/DataTypes.sol";
import {FeeManagerTest} from "test/unit/FeeManager/FeeManager.t.sol";
import {FeeManager} from "src/FeeManager.sol";

contract SetTreasuryActionFeeTest is FeeManagerTest {
    address public treasury = makeAddr("treasury");

    function setUp() public override {
        super.setUp();

        _setTreasury(feeManagerRole, treasury);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setTreasuryActionFee(uint256 actionNum, uint256 fee) public {
        ExternalAction action = ExternalAction(actionNum % 2);
        fee = bound(fee, 0, feeManager.MAX_FEE());

        vm.expectEmit(true, true, true, true);
        emit IFeeManager.TreasuryActionFeeSet(action, fee);

        _setTreasuryActionFee(feeManagerRole, action, fee);

        assertEq(feeManager.getTreasuryActionFee(action), fee);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setTreasuryActionFee_CallerIsNotFeeManagerRole(address caller, uint256 actionNum, uint256 fee)
        public
    {
        vm.assume(caller != feeManagerRole);
        ExternalAction action = ExternalAction(actionNum % 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, feeManager.FEE_MANAGER_ROLE()
            )
        );
        _setTreasuryActionFee(caller, action, fee);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setTreasuryActionFee_RevertIf_FeeTooHigh(uint256 actionNum, uint256 fee) public {
        ExternalAction action = ExternalAction(actionNum % 2);
        fee = bound(fee, feeManager.MAX_FEE() + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeTooHigh.selector, fee, feeManager.MAX_FEE()));
        _setTreasuryActionFee(feeManagerRole, action, fee);
    }

    function test_setTreasuryActionFee_RevertIf_TreasuryNotSet() public {
        _setTreasury(feeManagerRole, address(0));

        vm.expectRevert(abi.encodeWithSelector(IFeeManager.TreasuryNotSet.selector));
        _setTreasuryActionFee(feeManagerRole, ExternalAction.Deposit, 100);
    }
}
