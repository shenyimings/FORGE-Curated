// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.22;

abstract contract SelfCallable {
    /// @notice Error thrown when attempting to call a function from an invalid address.
    error OnlySelfCall();

    /**
     * @dev Restricts access to functions so they can only be called via this contract itself.
     */
    modifier onlySelfCall() {
        if (msg.sender != address(this)) revert OnlySelfCall();
        _;
    }
}
