// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { GovernanceAction } from "./IGovernanceController.sol";

library GovernanceMessageEVMCodec {
    uint8 private constant ACTION_OFFSET = 0;
    uint8 private constant ORIGIN_CALLER_OFFSET = ACTION_OFFSET + 1;
    uint8 private constant GOVERNED_CONTRACT_OFFSET = ORIGIN_CALLER_OFFSET + 32;
    uint8 private constant CALLDATA_OFFSET = GOVERNED_CONTRACT_OFFSET + 20;

    /*
     * @dev General purpose governance message to call arbitrary methods on a governed EVM smart contract.
     *      The wire format for this message is:
     *      - action - 1 byte
     *      - originCaller - 32 bytes
     *      - governedContract - 20 bytes
     *      - callData - remaining bytes
     */
    struct GovernanceMessage {
        uint8 action;
        bytes32 originCaller;
        address governedContract;
        bytes callData;
    }

    error InvalidAction(uint8 action);
    error InvalidMessageLength();

    function encode(GovernanceMessage memory _message) internal pure returns (bytes memory encoded) {
        if (_message.action != uint8(GovernanceAction.EVM_CALL)) {
            revert InvalidAction(_message.action);
        }

        return abi.encodePacked(
            _message.action,
            _message.originCaller,
            _message.governedContract,
            _message.callData
        );
    }

    function decode(bytes calldata _msg) internal pure returns (GovernanceMessage memory message) {
        if (_msg.length < CALLDATA_OFFSET) revert InvalidMessageLength();
        if (uint8(_msg[ACTION_OFFSET]) != uint8(GovernanceAction.EVM_CALL)) {
            revert InvalidAction(uint8(_msg[ACTION_OFFSET]));
        }
        
        message.action = uint8(_msg[ACTION_OFFSET]);
        message.originCaller = bytes32(_msg[ORIGIN_CALLER_OFFSET:GOVERNED_CONTRACT_OFFSET]);
        message.governedContract = address(uint160(bytes20(_msg[GOVERNED_CONTRACT_OFFSET:CALLDATA_OFFSET])));
        
        message.callData = _msg[CALLDATA_OFFSET:];
    }
}