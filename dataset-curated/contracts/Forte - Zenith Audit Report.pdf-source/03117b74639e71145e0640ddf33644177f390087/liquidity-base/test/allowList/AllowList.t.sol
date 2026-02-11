/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IAllowListEvents} from "src/common/IEvents.sol";
import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import {AllowList} from "src/allowList/AllowList.sol";
import "forge-std/console2.sol";
/**
 * @title Test PoolFactory contract
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55
 */
abstract contract AllowListTest is TestCommonSetup {
    AllowList allowList;
    function testAllowList_AllowList_deployment() public endWithStopPrank startAsAdmin {
        vm.expectEmit(true, true, true, true);
        emit IAllowListEvents.AllowListDeployed();
        allowList = new AllowList();
    }

    function _buildDeployment() internal startAsAdmin endWithStopPrank {
        allowList = new AllowList();
    }

    function _buildAddAllowedAddress() internal endWithStopPrank {
        _buildDeployment();
        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true, address(allowList));
        emit IAllowListEvents.AddressAllowed(admin, true);
        allowList.addToAllowList(admin);
    }

    function testAllowList_AllowList_addWhiteListDeployer_Positive() public endWithStopPrank {
        _buildAddAllowedAddress();
        vm.startPrank(admin);
        assertTrue(allowList.isAllowed(admin));
    }

    function testAllowList_AllowList_addWhiteListDeployer_Negative() public endWithStopPrank {
        _buildDeployment();
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        allowList.addToAllowList(admin);
    }

    function testAllowList_AllowList_removeWhiteListDeployer_Positive() public {
        _buildAddAllowedAddress();
        vm.startPrank(admin);
        vm.expectEmit(true, true, true, true, address(allowList));
        emit IAllowListEvents.AddressAllowed(admin, false);
        allowList.removeFromAllowList(address(admin));
        assertFalse(allowList.isAllowed(admin));
    }

    function testAllowList_AllowList_removeWhiteListDeployer_Negative() public endWithStopPrank {
        _buildAddAllowedAddress();
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        allowList.removeFromAllowList(admin);
    }
}
