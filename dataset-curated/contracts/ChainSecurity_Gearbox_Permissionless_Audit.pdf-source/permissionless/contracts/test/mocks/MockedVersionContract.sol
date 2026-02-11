// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

contract MockedVersionContract is IVersion {
    bytes32 public immutable contractType;
    uint256 public immutable version;

    constructor(bytes32 _contractType, uint256 _version) {
        contractType = _contractType;
        version = _version;
    }
}
