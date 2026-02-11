// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/// @title IRollupVerifier
/// @notice The interface for rollup verifier.
interface IZkRollupVerifier {
    /// @notice Verify zk proof.
    /// @param aggrProof The aggregated proof.
    /// @param publicInputHash The public input hash.
    function verifyProof(
        bytes calldata aggrProof,
        bytes calldata publicInputHash
    ) external view;

}
