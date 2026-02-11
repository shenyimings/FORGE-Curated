// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {DeploySonicStaking} from "script/DeploySonicStaking.sol";
import {SonicStaking} from "src/SonicStaking.sol";
import {ISFC} from "src/interfaces/ISFC.sol";
import {SonicStakingTestSetup} from "./SonicStakingTestSetup.sol";

contract SonicStakingAccessTest is Test, SonicStakingTestSetup {
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error OwnableUnauthorizedAccount(address account);

    function testOperatorRoleDeny() public {
        assertTrue(sonicStaking.hasRole(sonicStaking.OPERATOR_ROLE(), SONIC_STAKING_OPERATOR));

        address user = vm.addr(200);
        assertFalse(sonicStaking.hasRole(sonicStaking.OPERATOR_ROLE(), address(user)));

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user, sonicStaking.OPERATOR_ROLE())
        );
        sonicStaking.delegate(1, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user, sonicStaking.OPERATOR_ROLE())
        );
        sonicStaking.operatorInitiateClawBack(1, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user, sonicStaking.OPERATOR_ROLE())
        );
        sonicStaking.operatorExecuteClawBack(1, false);

        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user, sonicStaking.OPERATOR_ROLE())
        );
        sonicStaking.pause();

        vm.stopPrank();
    }

    function testAdminDeny() public {
        assertEq(sonicStaking.owner(), SONIC_STAKING_OWNER);

        address user = vm.addr(200);
        assertFalse(sonicStaking.owner() == address(user));

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user, sonicStaking.DEFAULT_ADMIN_ROLE())
        );
        sonicStaking.setWithdrawDelay(7);

        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user, sonicStaking.DEFAULT_ADMIN_ROLE())
        );
        sonicStaking.setUndelegatePaused(true);

        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user, sonicStaking.DEFAULT_ADMIN_ROLE())
        );
        sonicStaking.setWithdrawPaused(true);

        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user, sonicStaking.DEFAULT_ADMIN_ROLE())
        );
        sonicStaking.setDepositPaused(true);

        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user, sonicStaking.DEFAULT_ADMIN_ROLE())
        );
        sonicStaking.setTreasury(address(user));

        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user, sonicStaking.DEFAULT_ADMIN_ROLE())
        );
        sonicStaking.setProtocolFeeBIPS(9_000);

        vm.stopPrank();
    }

    function testClaimorRoleDeny() public {
        assertTrue(sonicStaking.hasRole(sonicStaking.CLAIM_ROLE(), SONIC_STAKING_CLAIMOR));

        address user = vm.addr(200);
        assertFalse(sonicStaking.hasRole(sonicStaking.CLAIM_ROLE(), address(user)));

        uint256[] memory delegationIds = new uint256[](1);
        delegationIds[0] = 1;
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user, sonicStaking.CLAIM_ROLE())
        );
        sonicStaking.claimRewards(delegationIds);

        vm.stopPrank();
    }
}
