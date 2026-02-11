// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Auth} from "@src/Auth.sol";
import {BaseTest} from "@test/BaseTest.t.sol";

contract AuthTest is BaseTest, Initializable {
  function test_Auth_initialize_null_address() public {
    Auth newAuth = new Auth();
    vm.store(address(newAuth), _initializableStorageSlot(), bytes32(uint256(0)));
    vm.expectRevert(abi.encodeWithSelector(Auth.NullAddress.selector));
    newAuth.initialize(address(0));
  }

  function test_Auth_upgrade() public {
    Auth newAuth = new Auth();
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE));
    auth.upgradeToAndCall(address(newAuth), abi.encodeCall(Auth.initialize, (alice)));

    vm.prank(admin);
    auth.upgradeToAndCall(address(newAuth), "");
  }
}
