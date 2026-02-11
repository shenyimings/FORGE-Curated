// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultMock} from "@test/mocks/VaultMock.t.sol";
import {Script, console} from "forge-std/Script.sol";

contract VaultMockScript is Script {
  address owner;
  IERC20 asset;
  string name;
  string symbol;

  function setUp() public {
    owner = vm.envAddress("OWNER");
    asset = IERC20(vm.envAddress("ASSET"));
    name = vm.envString("NAME");
    symbol = vm.envString("SYMBOL");
  }

  function run() public {
    vm.startBroadcast();

    deploy(owner, asset, name, symbol);

    vm.stopBroadcast();
  }

  function deploy(address owner_, IERC20 asset_, string memory name_, string memory symbol_) public returns (VaultMock) {
    return new VaultMock(owner_, asset_, name_, symbol_);
  }
}
