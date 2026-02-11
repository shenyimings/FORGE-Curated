// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @notice The IBlockHashProver is responsible for retrieving the block hash of its target chain given its home chain's state.
///         The home chain's state is given either by a block hash and proof, or by the BlockHashProver executing on the home chain.
///         A single home and target chain are fixed by the logic of this contract.
interface IBlockHashProver {
    /// @notice Verify the block hash of the target chain given the block hash of the home chain and a proof.
    /// @dev    MUST revert if called on the home chain.
    ///         MUST revert if the input is invalid or the input is not sufficient to determine the block hash.
    ///         MUST return a target chain block hash.
    ///         MUST be pure, with 1 exception: MAY read address(this).code.
    /// @param  homeBlockHash The block hash of the home chain.
    /// @param  input Any necessary input to determine a target chain block hash from the home chain block hash.
    /// @return targetBlockHash The block hash of the target chain.
    function verifyTargetBlockHash(bytes32 homeBlockHash, bytes calldata input)
        external
        view
        returns (bytes32 targetBlockHash);

    /// @notice Get the block hash of the target chain. Does so by directly access state on the home chain.
    /// @dev    MUST revert if not called on the home chain.
    ///         MUST revert if the target chain's block hash cannot be determined.
    ///         MUST return a target chain block hash.
    ///         SHOULD use the input to determine a specific block hash to return. (e.g. input could be a block number)
    ///         SHOULD NOT read from its own storage. This contract is not meant to have state.
    ///         MAY make external calls.
    /// @param  input Any necessary input to fetch a target chain block hash.
    /// @return targetBlockHash The block hash of the target chain.
    function getTargetBlockHash(bytes calldata input) external view returns (bytes32 targetBlockHash);

    /// @notice Verify a storage slot given a target chain block hash and a proof.
    /// @dev    This function MUST NOT assume it is being called on the home chain.
    ///         MUST revert if the input is invalid or the input is not sufficient to determine a storage slot and its value.
    ///         MUST return a storage slot and its value on the target chain
    ///         MUST be pure, with 1 exception: MAY read address(this).code.
    /// @param  targetBlockHash The block hash of the target chain.
    /// @param  input Any necessary input to determine a single storage slot and its value.
    /// @return account The address of the account on the target chain.
    /// @return slot The storage slot of the account on the target chain.
    /// @return value The value of the storage slot.
    function verifyStorageSlot(bytes32 targetBlockHash, bytes calldata input)
        external
        view
        returns (address account, uint256 slot, bytes32 value);

    /// @notice The version of the block hash prover.
    /// @dev    MUST be pure, with 1 exception: MAY read address(this).code.
    function version() external pure returns (uint256);
}
