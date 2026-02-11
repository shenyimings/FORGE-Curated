// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {ITimeLock} from "../interfaces/ITimeLock.sol";

contract TimeLock is ITimeLock {
    uint256 public constant override GRACE_PERIOD = 14 days;
    uint256 public constant override MINIMUM_DELAY = 1 days;
    uint256 public constant override MAXIMUM_DELAY = 30 days;

    address public immutable override admin;
    uint256 public override delay;

    mapping(bytes32 txHash => bool) public override queuedTransactions;

    modifier onlySelf() {
        if (msg.sender != address(this)) revert CallerIsNotSelfException(msg.sender);
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert CallerIsNotAdminException(msg.sender);
        _;
    }

    constructor(address admin_, uint256 delay_) {
        if (delay_ < MINIMUM_DELAY || delay_ > MAXIMUM_DELAY) revert IncorrectDelayException();

        admin = admin_;
        delay = delay_;
    }

    receive() external payable {}

    function setDelay(uint256 newDelay) external override onlySelf {
        if (newDelay < MINIMUM_DELAY || newDelay > MAXIMUM_DELAY) revert IncorrectDelayException();
        delay = newDelay;

        emit NewDelay(newDelay);
    }

    function queueTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta)
        external
        onlyAdmin
        returns (bytes32)
    {
        if (eta < block.timestamp + delay) revert DelayNotSatisfiedException();

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit QueueTransaction(txHash, target, value, signature, data, eta);
        return txHash;
    }

    function cancelTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta)
        external
        onlyAdmin
    {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = false;

        emit CancelTransaction(txHash, target, value, signature, data, eta);
    }

    function executeTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta)
        external
        payable
        onlyAdmin
        returns (bytes memory)
    {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        if (!queuedTransactions[txHash]) revert TransactionIsNotQueuedException(txHash);
        if (block.timestamp > eta) revert TimelockNotSurpassedException();
        if (block.timestamp > eta + GRACE_PERIOD) revert StaleTransactionException(txHash);

        queuedTransactions[txHash] = false;

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        if (!success) revert TransactionExecutionRevertedException(txHash);

        emit ExecuteTransaction(txHash, target, value, signature, data, eta);

        return returnData;
    }
}
