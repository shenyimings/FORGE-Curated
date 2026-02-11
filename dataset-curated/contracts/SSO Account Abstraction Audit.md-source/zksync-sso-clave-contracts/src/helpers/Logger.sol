// SPDX-License-Identifier: MIT
// A wrapper for the hardhat console so we can disable it at compile time
// instead of commenting out all the console.log statements :)
pragma solidity ^0.8.24;

import "hardhat/console.sol";

library Logger {
  function logString(string memory message) internal view {
    if (block.chainid == 260) {
      console.log(message);
    }
  }

  function logAddress(address addressToLog) internal view {
    if (block.chainid == 260) {
      console.log(addressToLog);
    }
  }

  function logBytes32(bytes32 bytesToLog) internal view {
    if (block.chainid == 260) {
      console.logBytes32(bytesToLog);
    }
  }

  function logUint(uint256 intToLog) internal view {
    if (block.chainid == 260) {
      console.logUint(intToLog);
    }
  }

  function logBool(bool boolToLog) internal view {
    if (block.chainid == 260) {
      console.logBool(boolToLog);
    }
  }
}
