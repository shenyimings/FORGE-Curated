// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IBroadcaster} from "./interfaces/IBroadcaster.sol";

import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

contract Broadcaster is IBroadcaster {
    error MessageAlreadyBroadcasted();

    function broadcastMessage(bytes32 message) external {
        // calculate the storage slot for the message
        bytes32 slot = _computeMessageSlot(message, msg.sender);

        // ensure the message has not already been broadcast

        if (_loadStorageSlot(slot) != 0) {
            revert MessageAlreadyBroadcasted();
        }

        // store the message and its timestamp
        _writeStorageSlot(slot, block.timestamp);

        // emit the event
        emit MessageBroadcast(message, msg.sender);
    }

    /// @dev Not required by the standard, but useful for visibility.
    function hasBroadcasted(bytes32 message, address publisher) external view returns (bool) {
        return _loadStorageSlot(_computeMessageSlot(message, publisher)) != 0;
    }

    /// @dev Helper function to store a value in a storage slot.
    function _writeStorageSlot(bytes32 slot, uint256 value) internal {
        StorageSlot.getUint256Slot(slot).value = value;
    }

    /// @dev Helper function to load a storage slot.
    function _loadStorageSlot(bytes32 slot) internal view returns (uint256 value) {
        value = StorageSlot.getUint256Slot(slot).value;
    }

    /// @dev Helper function to calculate the storage slot for a message.
    function _computeMessageSlot(bytes32 message, address publisher) internal pure returns (bytes32) {
        return keccak256(abi.encode(message, publisher));
    }
}
