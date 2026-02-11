// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { AsBNB } from "../src/AsBNB.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Run this command to test
// forge clean && forge build && forge test -vvv --match-contract AsBnbTest

contract AsBnbTest is Test {
  using SafeERC20 for AsBNB;

  address originalOwner = makeAddr("originalOwner");
  address newOwner = makeAddr("newOwner");

  AsBNB asBNB;

  function setUp() public {
    // fork testnet
    string memory url = vm.envString("TESTNET_RPC");
    vm.createSelectFork(url);

    // deploy AsBNB
    asBNB = new AsBNB("Astherus BNB", "asBNB", originalOwner, originalOwner);

    // give all roles some BNB
    deal(originalOwner, 100000 ether);
    deal(newOwner, 100000 ether);
  }

  function test_ownership2step() public {
    // check owner
    assertEq(asBNB.owner(), originalOwner);

    // transfer ownership
    vm.prank(originalOwner);
    asBNB.transferOwnership(newOwner);
    assertEq(asBNB.owner(), originalOwner);

    // only newOwner can accept ownership
    vm.prank(originalOwner);
    vm.expectRevert();
    asBNB.acceptOwnership();
    assertEq(asBNB.owner(), originalOwner);

    // accept ownership
    vm.prank(newOwner);
    asBNB.acceptOwnership();
    assertEq(asBNB.owner(), newOwner);
  }
}
