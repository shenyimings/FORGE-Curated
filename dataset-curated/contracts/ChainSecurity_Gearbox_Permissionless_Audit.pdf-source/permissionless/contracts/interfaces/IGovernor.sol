// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

/// @title Governor interface
interface IGovernor is IVersion {
    // ----- //
    // TYPES //
    // ----- //

    /// @notice Timelock contract transaction params packed in a struct
    /// @param target Target contract to call
    /// @param value Value to send in the call
    /// @param signature Signature of the target contract's function to call
    /// @param data ABI-encoded parameters to call the function with
    /// @param eta Transaction ETA (timestamp after which it can be executed)
    struct TxParams {
        address target;
        uint256 value;
        string signature;
        bytes data;
        uint256 eta;
    }

    /// @notice Batch information
    /// @param initiator Queue admin that initiated the batch
    /// @param length Number of transactions in the batch
    /// @param eta ETA of transactions in the batch
    struct BatchInfo {
        address initiator;
        uint16 length;
        uint80 eta;
    }

    /// @notice Batched transaction information
    /// @param batchBlock Block the batch was initiated in
    /// @param index Index of transaction within the batch
    struct BatchedTxInfo {
        uint64 batchBlock;
        uint16 index;
    }

    /// @notice Action that can be performed with a queued transaction
    enum TxAction {
        Execute,
        Cancel
    }

    // ------ //
    // EVENTS //
    // ------ //

    /// @notice Emitted when `caller` initiates a batch in `batchBlock`
    event QueueBatch(address indexed caller, uint256 indexed batchBlock);

    /// @notice Emitted when `caller` executes a batch initiated in `batchBlock`
    event ExecuteBatch(address indexed caller, uint256 indexed batchBlock);

    /// @notice Emitted when `caller` cancels a batch initiated in `batchBlock`
    event CancelBatch(address indexed caller, uint256 indexed batchBlock);

    /// @notice Emitted when `admin` is added to the list of queue admins
    event AddQueueAdmin(address indexed admin);

    /// @notice Emitted when `admin` is removed from the list of queue admins
    event RemoveQueueAdmin(address indexed admin);

    /// @notice Emitted when `admin` is added to the list of execution admins
    event AddExecutionAdmin(address indexed admin);

    /// @notice Emitted when `admin` is removed from the list of execution admins
    event RemoveExecutionAdmin(address indexed admin);

    /// @notice Emitted when `admin` is set as the new veto admin
    event UpdateVetoAdmin(address indexed admin);

    /// @notice Emitted when permissionless transaction/batch execution is allowed
    event AllowPermissionlessExecution();

    /// @notice Emitted when permissionless transaction/batch execution is forbidden
    event ForbidPermissionlessExecution();

    // ------ //
    // ERRORS //
    // ------ //

    /// @notice Thrown when an account that is not one of queue admins tries to queue a transaction or initiate a batch
    error CallerNotQueueAdminException();

    /// @notice Thrown when an account that is not one of execution admins tries to execute a transaction or a batch
    error CallerNotExecutionAdminException();

    /// @notice Thrown when an account that is not the timelock contract tries to configure the governor
    error CallerNotTimelockException();

    /// @notice Thrown when an account that is not the veto admin tries to cancel a transaction or a batch
    error CallerNotVetoAdminException();

    /// @notice Thrown when a queue admin tries to add transactions to the batch not initiated by themselves
    error CallerNotBatchInitiatorException();

    /// @notice Thrown when trying to queue a transaction that is already queued
    error TransactionAlreadyQueuedException();

    /// @notice Thrown when batched transaction's ETA differs from the batch ETA
    error ETAMistmatchException();

    /// @notice Thrown when trying to initiate a batch more than once in a block
    error BatchAlreadyStartedException();

    /// @notice Thrown when trying to execute or cancel a transaction individually while it's part of some batch
    error CantPerformActionOutsideBatchException();

    /// @notice Thrown when a passed list of transactions doesn't represent a valid queued batch
    error IncorrectBatchException();

    /// @notice Thrown when a passed list of transactions contains a transaction different from those in the queued batch
    error UnexpectedTransactionException(bytes32 txHash);

    /// @notice Thrown when trying to set zero address as a queue, execution or veto admin
    error AdminCantBeZeroAddressException();

    // ----- //
    // STATE //
    // ----- //

    /// @notice Returns an address of the timelock contract
    function timeLock() external view returns (address);

    /// @notice Returns an array of addresses of queue admins
    function queueAdmins() external view returns (address[] memory);

    /// @notice Returns an array of addresses of execution admins
    function executionAdmins() external view returns (address[] memory);

    /// @notice Returns an address of the veto admin
    function vetoAdmin() external view returns (address);

    /// @notice Whether permissionless transaction/batch execution is allowed
    function isPermissionlessExecutionAllowed() external view returns (bool);

    /// @notice Returns info for the batch initiated in `batchBlock`
    /// @dev `initiator == address(0)` means that there was no batch initiated in that block
    function batchInfo(uint256 batchBlock) external view returns (address initiator, uint16 length, uint80 eta);

    /// @notice Returns batch info for the transaction with given `txHash`
    /// @dev `batchBlock == 0` means that transaction is not part of any batch
    function batchedTxInfo(bytes32 txHash) external view returns (uint64 batchBlock, uint16 index);

    // ------- //
    // ACTIONS //
    // ------- //

    /// @notice Queues a transaction in the timelock. Ensures that it's not already queued. When no batch is initiated,
    ///         simply forwards the call to the timelock contract. Otherwise, appends the transaction to the batch after
    ///         checking that caller is the account that initiated the batch and ETAs of all transactions are the same.
    /// @dev See `TxParams` for params description
    /// @dev Can only be called by queue admins
    function queueTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external returns (bytes32 txHash);

    /// @notice Initiates a batch of transactions. All the transactions that are queued after this call in the same block
    ///         will form a batch that can only be executed/cancelled as a whole. Typically, this will be the first call
    ///         in a multicall that queues a batch, followed by multiple `queueTransaction` calls.
    /// @param eta ETA of transactions in the batch
    /// @dev Can only be called by queue admins
    function startBatch(uint80 eta) external;

    /// @notice Executes a queued transaction. Ensures that it is not part of any batch and forwards the call to the
    ///         timelock contract.
    /// @dev See `TxParams` for params description
    /// @dev Can only be called by execution admins unless permissionless execution is allowed
    function executeTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external payable returns (bytes memory result);

    /// @notice Executes a queued batch of transactions. Ensures that `txs` is the same ordered list of transactions as
    ///         the one that was queued, and forwards all calls to the timelock contract.
    /// @dev Can only be called by execution admins unless permissionless execution is allowed
    function executeBatch(TxParams[] calldata txs) external payable;

    /// @notice Cancels a queued transaction. Ensures that it is not part of any batch and forwards the call to the
    ///         timelock contract.
    /// @dev See `TxParams` for params description
    /// @dev Can only be called by the veto admin
    function cancelTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external;

    /// @notice Cancels a queued batch of transactions. Ensures that `txs` is the same ordered list of transactions as
    ///         the one that was queued, and forwards all calls to the timelock contract.
    /// @dev Can only be called by the veto admin
    function cancelBatch(TxParams[] calldata txs) external;

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    /// @notice Adds `admin` to the list of queue admins, ensures that it's not zero address
    /// @dev Can only be called by the timelock contract
    function addQueueAdmin(address admin) external;

    /// @notice Removes `admin` from the list of queue admins
    /// @dev Can only be called by the timelock contract
    function removeQueueAdmin(address admin) external;

    /// @notice Adds `admin` to the list of execution admins, ensures that it's not zero address
    /// @dev Can only be called by the timelock contract
    function addExecutionAdmin(address admin) external;

    /// @notice Removes `admin` from the list of execution admins
    /// @dev Can only be called by the timelock contract
    function removeExecutionAdmin(address admin) external;

    /// @notice Sets `admin` as the new veto admin, ensures that it's not zero address
    /// @dev Can only be called by the timelock contract
    /// @dev It's assumed that veto admin is a contract that has means to prevent it from blocking its' own update,
    ///      for example, it might be a multisig that can remove malicious signers
    function updateVetoAdmin(address admin) external;

    /// @notice Allows permissionless transactions/batches execution
    /// @dev Can only be called by the timelock contract
    function allowPermissionlessExecution() external;

    /// @notice Forbids permissionless transactions/batches execution
    /// @dev Can only be called by the timelock contract
    function forbidPermissionlessExecution() external;
}
