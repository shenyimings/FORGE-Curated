// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvPool} from "./SetupStvPool.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {FeaturePausable} from "src/utils/FeaturePausable.sol";

contract DepositsPauseTest is Test, SetupStvPool {
    address public depositsPauseRoleHolder;
    address public depositsResumeRoleHolder;

    bytes32 depositsFeatureId;

    function setUp() public override {
        super.setUp();

        depositsPauseRoleHolder = makeAddr("depositsPauseRoleHolder");
        depositsResumeRoleHolder = makeAddr("depositsResumeRoleHolder");

        vm.deal(depositsPauseRoleHolder, 10 ether);
        vm.deal(depositsResumeRoleHolder, 10 ether);

        vm.startPrank(owner);
        pool.grantRole(pool.DEPOSITS_PAUSE_ROLE(), depositsPauseRoleHolder);
        pool.grantRole(pool.DEPOSITS_RESUME_ROLE(), depositsResumeRoleHolder);
        vm.stopPrank();

        depositsFeatureId = pool.DEPOSITS_FEATURE();
        vm.deal(address(this), 100 ether);
    }

    function test_DepositETH_RevertWhenPaused() public {
        vm.prank(depositsPauseRoleHolder);
        pool.pauseDeposits();

        vm.expectRevert(abi.encodeWithSelector(FeaturePausable.FeaturePauseEnforced.selector, depositsFeatureId));
        pool.depositETH{value: 1 ether}(address(this), address(0));
    }

    function test_PauseDeposits_RevertWhenCallerUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), pool.DEPOSITS_PAUSE_ROLE()
            )
        );
        pool.pauseDeposits();
    }

    function test_ResumeDeposits_RevertWhenCallerUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), pool.DEPOSITS_RESUME_ROLE()
            )
        );
        pool.resumeDeposits();
    }

    function test_ResumeDeposits_AllowsDepositsAfterPause() public {
        vm.prank(depositsPauseRoleHolder);
        pool.pauseDeposits();

        vm.prank(depositsResumeRoleHolder);
        pool.resumeDeposits();

        uint256 mintedStv = pool.depositETH{value: 1 ether}(address(this), address(0));
        assertGt(mintedStv, 0);
    }
}
