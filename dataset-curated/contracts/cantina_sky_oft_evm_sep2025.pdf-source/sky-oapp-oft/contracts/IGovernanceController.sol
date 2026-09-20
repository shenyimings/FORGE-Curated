// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

struct GovernanceOrigin {
    uint32 eid; // LayerZero Endpoint ID
    bytes32 caller; // Caller on the source chain
}

/// @notice The known set of governance actions.
enum GovernanceAction {
    UNDEFINED,
    EVM_CALL,
    SOLANA_CALL
}

interface IGovernanceController {
    function messageOrigin() external view returns (uint32 eid, bytes32 caller);
}
