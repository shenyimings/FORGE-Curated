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

contract SetLeverageTokenActionFeeTest is FeeManagerTest {
    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setLeverageTokenActionFee(ILeverageToken leverageToken, uint256 actionNum, uint256 fee) public {
        ExternalAction action = ExternalAction(actionNum % 2);
        fee = bound(fee, 0, feeManager.MAX_FEE());

        vm.expectEmit(true, true, true, true);
        emit IFeeManager.LeverageTokenActionFeeSet(leverageToken, action, fee);

        feeManager.exposed_setLeverageTokenActionFee(leverageToken, action, fee);

        assertEq(feeManager.getLeverageTokenActionFee(leverageToken, action), fee);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setLeverageTokenActionFee_RevertIfFeeTooHigh(
        ILeverageToken leverageToken,
        uint256 actionNum,
        uint256 fee
    ) public {
        ExternalAction action = ExternalAction(actionNum % 2);
        fee = bound(fee, feeManager.MAX_FEE() + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeTooHigh.selector, fee, feeManager.MAX_FEE()));
        feeManager.exposed_setLeverageTokenActionFee(leverageToken, action, fee);
    }
}
