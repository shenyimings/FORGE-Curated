// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {BuilderCodes} from "../../src/BuilderCodes.sol";

// Create a mock V2 contract for testing upgrades
contract BuilderCodesV2 is BuilderCodes {
    uint256 public totalPublishersCreated;

    function incrementTotalPublishers() external onlyOwner {
        totalPublishersCreated++;
    }

    function version() external pure returns (string memory) {
        return "V2";
    }

    // adding this to be excluded from coverage report
    function test() public {}
}
