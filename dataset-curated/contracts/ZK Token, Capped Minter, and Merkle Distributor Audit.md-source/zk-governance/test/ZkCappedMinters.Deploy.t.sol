// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DeployZkTokenV1, DeployZkTokenV1Input} from "script/DeployZkTokenV1.s.sol";
import {DeployZkCappedMinters, DeployZkCappedMintersInput} from "script/DeployZkCappedMinters.s.sol";
import {ZkTokenV1} from "src/ZkTokenV1.sol";
import {ZkCappedMinter} from "src/ZkCappedMinter.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract ZkCappedMinteresDeployTest is DeployZkTokenV1Input, DeployZkCappedMintersInput, Test {
  ZkTokenV1 token;
  ZkCappedMinter associationCappedMinter;
  ZkCappedMinter foundationCappedMinter;

  function setUp() public {
    DeployZkTokenV1 _tokenDeployScript = new DeployZkTokenV1();
    _tokenDeployScript.setUp();
    token = _tokenDeployScript.run();
    DeployZkCappedMinters _cappedMintersDeployScript = new DeployZkCappedMinters();
    _cappedMintersDeployScript.setUp();
    (associationCappedMinter, foundationCappedMinter) = _cappedMintersDeployScript.run(address(token));
  }

  function test_DeploysTheCappedMintersAsExpected() public {
    assertEq(address(associationCappedMinter.TOKEN()), address(token));
    assertEq(associationCappedMinter.ADMIN(), ASSOCIATION_ADMIN_ACCOUNT);
    assertEq(associationCappedMinter.CAP(), ASSOCIATION_CAP_AMOUNT);

    assertEq(address(foundationCappedMinter.TOKEN()), address(token));
    assertEq(foundationCappedMinter.ADMIN(), FOUNDATION_ADMIN_ACCOUNT);
    assertEq(foundationCappedMinter.CAP(), FOUNDATION_CAP_AMOUNT);
  }
}
