// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

/// @title Timelock interface
interface ITimeLock {
    // ------ //
    // EVENTS //
    // ------ //

    event NewDelay(uint256 indexed newDelay);

    event CancelTransaction(
        bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta
    );

    event ExecuteTransaction(
        bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta
    );

    event QueueTransaction(
        bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta
    );

    // ------ //
    // ERRORS //
    // ------ //

    error CallerIsNotAdminException(address caller);

    error CallerIsNotSelfException(address caller);

    error DelayNotSatisfiedException();

    error IncorrectDelayException();

    error StaleTransactionException(bytes32 txHash);

    error TimelockNotSurpassedException();

    error TransactionIsNotQueuedException(bytes32 txHash);

    error TransactionExecutionRevertedException(bytes32 txHash);

    // --------------- //
    // STATE VARIABLES //
    // --------------- //

    function GRACE_PERIOD() external view returns (uint256);

    function MINIMUM_DELAY() external view returns (uint256);

    function MAXIMUM_DELAY() external view returns (uint256);

    function admin() external view returns (address);

    function delay() external view returns (uint256);

    // ------------ //
    // TRANSACTIONS //
    // ------------ //

    function queuedTransactions(bytes32 txHash) external view returns (bool);

    function queueTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta)
        external
        returns (bytes32 txHash);

    function executeTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta)
        external
        payable
        returns (bytes memory result);

    function cancelTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta)
        external;

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function setDelay(uint256 newDelay) external;
}
