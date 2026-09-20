// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { GovernanceMessageGenericCodec } from "../../../contracts/GovernanceMessageGenericCodec.sol";

contract GovernanceGenericCodecLibraryHelper {
    function assertValidMessageLength(bytes calldata message) external pure {
        GovernanceMessageGenericCodec.assertValidMessageLength(message);
    }
}