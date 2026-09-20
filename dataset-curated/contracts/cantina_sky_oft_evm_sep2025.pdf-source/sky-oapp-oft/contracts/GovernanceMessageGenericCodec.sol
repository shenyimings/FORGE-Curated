// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

library GovernanceMessageGenericCodec {
    uint8 private constant ACTION_OFFSET = 0;
    uint8 private constant ORIGIN_CALLER_OFFSET = ACTION_OFFSET + 1;

    error InvalidGenericMessageLength();

    function assertValidMessageLength(bytes calldata _msg) internal pure {
        if (_msg.length < ORIGIN_CALLER_OFFSET + 32) {
            revert InvalidGenericMessageLength();
        }
    }

    function action(bytes calldata _msg) internal pure returns (uint8) {
        return uint8(_msg[ACTION_OFFSET]);
    }

    function originCaller(bytes calldata _msg) internal pure returns (bytes32) {
        return bytes32(_msg[ORIGIN_CALLER_OFFSET:ORIGIN_CALLER_OFFSET+32]);
    }
}