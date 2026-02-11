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
    function testFuzz_setTreasury(address _treasury) public {
        vm.expectEmit(true, true, true, true);
        emit IFeeManager.TreasurySet(_treasury);

        _setTreasury(feeManagerRole, _treasury);
        assertEq(feeManager.getTreasury(), _treasury);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_setTreasury_RevertIf_CallerIsNotFeeManagerRole(address caller, address _treasury) public {
        vm.assume(caller != feeManagerRole);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, feeManager.FEE_MANAGER_ROLE()
            )
        );
        _setTreasury(caller, _treasury);
    }

    /// forge-config: default.fuzz.runs = 1
    function test_setTreasury_RevertIf_TreasuryIsZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IFeeManager.ZeroAddressTreasury.selector));
        _setTreasury(feeManagerRole, address(0));
    }
}
