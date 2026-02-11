// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";

contract LossSocializationLimiterTest is Test, SetupStvStETHPool {
    function test_MaxLossSocializationBP_DefaultsToZero() public view {
        assertEq(pool.maxLossSocializationBP(), 0);
    }

    function test_SetMaxLossSocializationBP_UpdatesStoredValue() public {
        uint16 newLimit = 2_500;

        vm.prank(owner);
        pool.setMaxLossSocializationBP(newLimit);

        assertEq(pool.maxLossSocializationBP(), newLimit);
    }

    function test_SetMaxLossSocializationBP_EmitsEvent() public {
        uint16 newLimit = 1_000;

        vm.expectEmit(false, false, false, true, address(pool));
        emit StvStETHPool.MaxLossSocializationUpdated(newLimit);

        vm.prank(owner);
        pool.setMaxLossSocializationBP(newLimit);
    }

    function test_SetMaxLossSocializationBP_RevertWhenCallerUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), pool.DEFAULT_ADMIN_ROLE()
            )
        );
        pool.setMaxLossSocializationBP(100);
    }

    function test_SetMaxLossSocializationBP_RevertWhenValueTooHigh() public {
        uint16 invalidLimit = uint16(pool.TOTAL_BASIS_POINTS() + 1);

        vm.startPrank(owner);
        vm.expectRevert(StvStETHPool.InvalidValue.selector);
        pool.setMaxLossSocializationBP(invalidLimit);
        vm.stopPrank();
    }

    function test_SetMaxLossSocializationBP_RevertWhenValueUnchanged() public {
        uint16 limit = 3_000;

        vm.startPrank(owner);
        pool.setMaxLossSocializationBP(limit);
        vm.expectRevert(StvStETHPool.SameValue.selector);
        pool.setMaxLossSocializationBP(limit);
        vm.stopPrank();
    }
}
