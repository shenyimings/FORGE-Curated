// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC1271} from "./IERC1271.sol";
import {IERC7821} from "./IERC7821.sol";

// Inspired by ERC-7579.
// https://eips.ethereum.org/EIPS/eip-7579
interface IValidator is IERC1271 {
    // Called by `validateUserOp` when using ERC-4337.
    // Called by `execute` when not using ERC-4337 and execution mode is `EXEC_MODE_OP_DATA` and
    // signature length is not 65 bytes.
    // Should return false on signature mismatch, any other error must revert.
    // Should not return early on signature mismatch to allow for accurate gas estimation.
    function validate(
        IERC7821.Call[] calldata calls,
        address sender,
        bytes32 digest,
        bytes calldata signature
    ) external returns (bool);

    // Called by `execute` after `calls` have been executed.
    // Validators are expected to use transient storage (EIP-1153) to pass context between
    // `validate` and `postExecute`.
    // WARNING: this context should be scoped to each account since `validate` could be called by
    // another account (overwriting the context) before `postExecute` is called on the original
    // account.
    function postExecute() external;
}
