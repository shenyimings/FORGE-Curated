// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Internal imports
import {FeeManagerTest} from "test/unit/FeeManager/FeeManager.t.sol";
import {FeeManager} from "src/FeeManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {IFeeManager} from "src/interfaces/IFeeManager.sol";

contract SetManagementFeeTest is FeeManagerTest {
    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setManagementFee(ILeverageToken token, uint256 managementFee) public {
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);

        vm.mockCall(
            address(token),
            abi.encodeWithSelector(ERC20.totalSupply.selector),
            abi.encode(100 ether) // Mocked so that the call to totalSupply does not revert
        );

        vm.expectEmit(true, true, true, true);
        emit IFeeManager.ManagementFeeSet(token, managementFee);
        _setManagementFee(feeManagerRole, token, managementFee);

        assertEq(feeManager.getManagementFee(token), managementFee);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setManagementFee_RevertIf_FeeTooHigh(ILeverageToken token, uint256 managementFee) public {
        managementFee = bound(managementFee, MAX_MANAGEMENT_FEE + 1, type(uint256).max);

        vm.mockCall(
            address(token),
            abi.encodeWithSelector(ERC20.totalSupply.selector),
            abi.encode(100 ether) // Mocked so that the call to totalSupply does not revert
        );

        vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeTooHigh.selector, managementFee, MAX_MANAGEMENT_FEE));
        vm.prank(feeManagerRole);
        feeManager.setManagementFee(token, managementFee);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setManagementFee_RevertIf_CallerIsNotFeeManagerRole(address caller, ILeverageToken token)
        public
    {
        vm.assume(caller != feeManagerRole);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, feeManager.FEE_MANAGER_ROLE()
            )
        );
        _setManagementFee(caller, token, 0);
    }

    function test_setManagementFee_ChargesOutstandingFees() public {
        uint256 managementFee = 0.1e4; // 10%
        _setManagementFee(feeManagerRole, leverageToken, managementFee);

        uint256 initialSupply = 100 ether;
        leverageToken.mint(address(this), initialSupply);

        skip(SECONDS_ONE_YEAR);

        uint256 expectedOutstandingFees = 10 ether;
        uint256 newManagementFee = 0.2e4;

        vm.expectEmit(true, true, true, true);
        emit IFeeManager.ManagementFeeCharged(leverageToken, expectedOutstandingFees);
        vm.expectEmit(true, true, true, true);
        emit IFeeManager.ManagementFeeSet(leverageToken, newManagementFee);
        _setManagementFee(feeManagerRole, leverageToken, newManagementFee);

        assertEq(leverageToken.totalSupply(), initialSupply + expectedOutstandingFees);
        assertEq(feeManager.getManagementFee(leverageToken), newManagementFee);
        assertEq(feeManager.getLastManagementFeeAccrualTimestamp(leverageToken), block.timestamp);
    }
}
