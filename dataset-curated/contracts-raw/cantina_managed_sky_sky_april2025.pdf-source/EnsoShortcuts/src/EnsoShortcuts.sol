// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import { VM } from "enso-weiroll/VM.sol";
import { MinimalWallet } from "shortcuts-contracts/wallet/MinimalWallet.sol";
import { AccessController } from "shortcuts-contracts/access/AccessController.sol";

contract EnsoShortcuts is VM, MinimalWallet, AccessController {
    address public executor;

    constructor(address owner_, address executor_) {
        _setPermission(OWNER_ROLE, owner_, true);
        executor = executor_;
    }

    // @notice Execute a shortcut
    // @param commands An array of bytes32 values that encode calls
    // @param state An array of bytes that are used to generate call data for each command
    function executeShortcut(
        bytes32[] calldata commands,
        bytes[] calldata state
    ) external payable returns (bytes[] memory) {
        // we could use the AccessController here to check if the msg.sender is the executor address
        // but as it's a hot path we do a less gas intensive check
        if (msg.sender != executor) revert NotPermitted();
        return _execute(commands, state);
    }
}
