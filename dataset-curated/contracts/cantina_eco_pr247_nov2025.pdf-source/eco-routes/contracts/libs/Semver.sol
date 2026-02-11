// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISemver} from "../interfaces/ISemver.sol";

/**
 * @title Semver
 * @notice Implements semantic versioning for contracts
 * @dev Abstract contract that provides a standard way to access version information
 */
abstract contract Semver is ISemver {
    /**
     * @notice Returns the semantic version of the contract
     * @dev Implementation of ISemver interface
     * @return Current version string in semantic format
     */
    function version() external pure returns (string memory) {
        return "2.6";
    }
}
