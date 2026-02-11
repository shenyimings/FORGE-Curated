// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { INonceManager } from "./INonceManager.sol";
import { IPermit } from "./IPermit.sol";

/**
 * @title IPermit3
 * @notice Interface for the Permit3 cross-chain token approval and transfer system using UnbalancedProofs
 */
interface IPermit3 is IPermit, INonceManager {
    /**
     * @notice Enum representing the type of permit operation
     * @param Transfer Execute immediate transfer
     * @param Decrease Decrease allowance
     * @param Lock Lock allowance
     * @param Unlock Unlock previously locked allowance
     */
    enum PermitType {
        Transfer,
        Decrease,
        Lock,
        Unlock
    }

    /**
     * @notice Represents a token allowance modification or transfer operation
     * @param modeOrExpiration Mode indicators:
     *        = 0: Immediate transfer mode
     *        = 1: Decrease allowance mode
     *        = 2: Lock allowance mode
     *        = 3: UnLock allowance mode
     *        > 3: Increase allowance mode, new expiration for the allowance if the timestamp is recent
     * @param token Address of the ERC20 token
     * @param account Transfer recipient (for mode 0) or approved spender (for allowance)
     * @param amountDelta Allowance change or transfer amount:
     *        - For transfer mode: Amount to transfer
     *        - For allowance mode: Increases or decreases allowance
     *           - 0: Only updates expiration
     *           - type(uint160).max: Unlimited approval or decrease to 0.
     */
    struct AllowanceOrTransfer {
        uint48 modeOrExpiration;
        address token;
        address account;
        uint160 amountDelta;
    }

    /**
     * @notice Struct grouping permits for a specific chain
     * @param chainId Target chain identifier
     * @param permits Array of permit operations for this chain
     */
    struct ChainPermits {
        uint64 chainId;
        AllowanceOrTransfer[] permits;
    }

    /**
     * @notice Returns the witness typehash stub for EIP-712 signature verification
     * @return The stub string for witness permit typehash
     */
    function PERMIT_WITNESS_TYPEHASH_STUB() external pure returns (string memory);

    /**
     * @notice Hashes chain permits data for cross-chain operations
     * @param chainPermits Chain-specific permit data
     * @return bytes32 Combined hash of all permit parameters
     */
    function hashChainPermits(
        ChainPermits memory chainPermits
    ) external pure returns (bytes32);

    /**
     * @notice Direct permit execution for ERC-7702 integration
     * @dev No signature verification - caller must be the token owner
     * @param permits Array of permit operations to execute on current chain
     */
    function permit(
        AllowanceOrTransfer[] memory permits
    ) external;

    /**
     * @notice Process permit for single chain token approvals
     * @param owner Token owner address
     * @param salt Unique salt for replay protection
     * @param deadline Signature expiration timestamp
     * @param timestamp Timestamp of the permit
     * @param permits Array of permit operations to execute
     * @param signature EIP-712 signature authorizing the permits
     */
    function permit(
        address owner,
        bytes32 salt,
        uint48 deadline,
        uint48 timestamp,
        AllowanceOrTransfer[] calldata permits,
        bytes calldata signature
    ) external;

    /**
     * @notice Process permit for multi-chain token approvals using Merkle Tree
     * @param owner Token owner address
     * @param salt Unique salt for replay protection
     * @param deadline Signature expiration timestamp
     * @param timestamp Timestamp of the permit
     * @param permits Permit operations for the current chain
     * @param proof Merkle proof array for verification
     * @param signature EIP-712 signature authorizing the batch
     */
    function permit(
        address owner,
        bytes32 salt,
        uint48 deadline,
        uint48 timestamp,
        ChainPermits calldata permits,
        bytes32[] calldata proof,
        bytes calldata signature
    ) external;

    /**
     * @notice Process permit with additional witness data for single chain operations
     * @param owner Token owner address
     * @param salt Unique salt for replay protection
     * @param deadline Signature expiration timestamp
     * @param timestamp Timestamp of the permit
     * @param permits Array of permit operations to execute
     * @param witness Additional data to include in signature verification
     * @param witnessTypeString EIP-712 type definition for witness data
     * @param signature EIP-712 signature authorizing the permits
     */
    function permitWitness(
        address owner,
        bytes32 salt,
        uint48 deadline,
        uint48 timestamp,
        AllowanceOrTransfer[] calldata permits,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external;

    /**
     * @notice Process permit with additional witness data for cross-chain operations
     * @param owner Token owner address
     * @param salt Unique salt for replay protection
     * @param deadline Signature expiration timestamp
     * @param timestamp Timestamp of the permit
     * @param permits Permit operations for the current chain
     * @param proof Merkle proof array for verification
     * @param witness Additional data to include in signature verification
     * @param witnessTypeString EIP-712 type definition for witness data
     * @param signature EIP-712 signature authorizing the batch
     */
    function permitWitness(
        address owner,
        bytes32 salt,
        uint48 deadline,
        uint48 timestamp,
        ChainPermits calldata permits,
        bytes32[] calldata proof,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external;
}
