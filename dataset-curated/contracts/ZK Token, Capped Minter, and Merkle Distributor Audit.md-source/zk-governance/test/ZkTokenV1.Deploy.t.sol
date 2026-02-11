// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DeployZkTokenV1, DeployZkTokenV1Input} from "script/DeployZkTokenV1.s.sol";
import {ZkTokenV1} from "src/ZkTokenV1.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract ZkTokenV1DeployTest is DeployZkTokenV1Input, Test {
  ZkTokenV1 token;

  // Placed here for convenience in tests. Must match the constants in the implementation.
  bytes32 public DEFAULT_ADMIN_ROLE = 0x00;
  bytes32 public MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public BURNER_ROLE = keccak256("BURNER_ROLE");
  bytes32 public MINTER_ADMIN_ROLE = keccak256("MINTER_ADMIN_ROLE");
  bytes32 public BURNER_ADMIN_ROLE = keccak256("BURNER_ADMIN_ROLE");

  function setUp() public {
    DeployZkTokenV1 _deployScript = new DeployZkTokenV1();
    _deployScript.setUp();
    token = _deployScript.run();
  }

  function test_DeploysTheTokenAsExpected() public {
    assertEq(token.symbol(), "ZK");
    assertEq(token.name(), "zkSync");

    // The association account has received the full minted distribution
    assertEq(token.balanceOf(INITIAL_MINT_ACCOUNT), INITIAL_MINT_AMOUNT);
    assertEq(token.totalSupply(), INITIAL_MINT_AMOUNT);

    // The association account has all three administrative roles after initialization
    assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, ADMIN_ACCOUNT));
    assertTrue(token.hasRole(MINTER_ADMIN_ROLE, ADMIN_ACCOUNT));
    assertTrue(token.hasRole(BURNER_ADMIN_ROLE, ADMIN_ACCOUNT));

    // The administrative roles have the proper association with each role
    assertEq(token.getRoleAdmin(MINTER_ROLE), MINTER_ADMIN_ROLE);
    assertEq(token.getRoleAdmin(BURNER_ROLE), BURNER_ADMIN_ROLE);

    // The administrative role of the administrative roles are the default admin
    assertEq(token.getRoleAdmin(MINTER_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
    assertEq(token.getRoleAdmin(BURNER_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);

    // The default administrative role self administers
    assertEq(token.getRoleAdmin(DEFAULT_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);

    // The association account is also the owner of the proxy admin
    bytes32 _proxyAdminSlot = vm.load(address(token), ERC1967Utils.ADMIN_SLOT);
    ProxyAdmin _proxyAdmin = ProxyAdmin(address(uint160(uint256(_proxyAdminSlot))));
    assertEq(_proxyAdmin.owner(), ADMIN_ACCOUNT);
  }
}
