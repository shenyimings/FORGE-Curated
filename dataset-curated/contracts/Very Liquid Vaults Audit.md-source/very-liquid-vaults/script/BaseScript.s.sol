// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ICreate2Deployer} from "@script/ICreate2Deployer.s.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract BaseScript is Script, ICreate2Deployer {
  ICreate2Deployer public create2Deployer = ICreate2Deployer(address(this));

  function setUp() public virtual {
    create2Deployer = ICreate2Deployer(0x13b0D85CcB8bf860b6b79AF3029fCA081AE9beF2);
  }

  function deploy(uint256 value, bytes32 salt, bytes memory code) public {
    Create2.deploy(value, salt, code);
  }

  function computeAddress(bytes32 salt, bytes32 codeHash) public view returns (address) {
    return Create2.computeAddress(salt, codeHash);
  }
}
