// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IMiddleware {
    /// @notice Subnetwork id
    /// @dev Creates a collision resistant uint96 identifier by taking keccak256 hash of agent address
    /// and using the first 96 bits of the hash
    /// @param _agent Agent address
    /// @return id Subnetwork identifier (first 96 bits of keccak256 hash of agent address)
    function subnetworkIdentifier(address _agent) external pure returns (uint96 id);

    /// @notice Subnetwork id concatenated with network address
    /// @return id Subnetwork id
    function subnetwork(address _agent) external view returns (bytes32 id);
}
