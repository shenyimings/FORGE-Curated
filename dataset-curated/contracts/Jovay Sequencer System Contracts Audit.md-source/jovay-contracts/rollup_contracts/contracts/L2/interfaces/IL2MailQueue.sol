// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IL2MailQueue {
    /**
     * @dev Returns the message root.
     */
    function msgRoot() external view returns (bytes32);
}
