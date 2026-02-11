// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract TimelockControllerFake is TimelockController {
  constructor(address _admin) TimelockController(0 days, new address[](0), new address[](0), _admin) {}
}
