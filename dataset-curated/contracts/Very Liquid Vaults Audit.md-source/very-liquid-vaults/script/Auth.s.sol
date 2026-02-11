// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Auth} from "@src/Auth.sol";
import {Script, console} from "forge-std/Script.sol";

contract AuthScript is Script {
  address admin;

  function setUp() public {
    admin = vm.envAddress("ADMIN");
  }

  function run() public {
    vm.startBroadcast();

    deploy(admin);

    vm.stopBroadcast();
  }

  function deploy(address admin_) public returns (Auth auth) {
    return Auth(address(new ERC1967Proxy(address(new Auth()), abi.encodeCall(Auth.initialize, (admin_)))));
  }
}
