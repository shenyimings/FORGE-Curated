// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title IRollupVerifier
/// @notice The interface for rollup verifier.
interface ITeeRollupVerifier {
    /// @notice Verify zk proof.
    /// @param aggrProof The aggregated proof.
    function verifyProof(bytes calldata aggrProof) external returns (uint32 _error_code, bytes32 commitment);
}
