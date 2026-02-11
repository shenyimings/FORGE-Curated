// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IFlashLoanRouter} from "src/interface/IFlashLoanRouter.sol";

/// @dev A basic contract framework for other contracts that are supposed to
/// call a specific function every time they are called. This function is
/// expected to revert with a specific message, extracted by this contract.
contract BaseForwarder {
    IFlashLoanRouter public router;

    /// @dev We use events to exfiltrate revert data in contexts where it can
    /// be hard to access otherwise.
    event RevertReason(string reason);

    function setRouter(IFlashLoanRouter _router) external {
        router = _router;
    }

    /// @dev Extract the revert reason string from the return value of a
    /// reverting low-level call.
    function emitRevertReason(bytes memory err) internal {
        string memory reason;
        // A string error in Solidity is returned as the ABI-encoding of a
        // function `Error(string)`. Including the overhead of having `err`
        // encoded, this means:
        // - 32 bytes of `err` length
        // - 4 bytes selector
        // - 32 bytes of pointer to the actual string
        // - 32 bytes of string length
        // - the actual string content
        // By moving the memory pointer forward by the first 3 steps, we get
        // a valid encoding of the error string in memory.
        assembly ("memory-safe") {
            reason := add(err, 68)
        }
        emit RevertReason(reason);
    }
}
