// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMailBoxBase {
    error InvalidInitAddress();

    error InvalidL2GasLimit();

    error SetL2GasLimitSmallerThanGasUsed();

    error SetL2FinalizeDepositGasUsedBiggerThanGasLimit();

    /// @notice Emitted when a message is sent.
    event SentMsg(
        address indexed sender,
        address indexed target,
        uint256 value,
        uint256 nonce,
        bytes msg,
        uint256 gasLimit,
        bytes32 hash
    );

    /// @notice Emitted when a finalize deposit message is relayed failed.
    event FinalizeDepositETHFailed(bytes32 indexed hash, uint256 nonce);

    /// @notice Emitted when a finalize deposit message is relayed success.
    event FinalizeDepositETHSuccess(bytes32 indexed hash, uint256 nonce);

    /// @notice Emitted when a cross domain message is relayed successfully.
    event RelayedMsg(bytes32 indexed hash, uint256 nonce);

    /// @notice Emitted when a cross domain message is relayed successfully.
    event ClaimMsg(bytes32 indexed hash, uint256 nonce);

    /// @notice Emitted when a cross domain message is failed to relay.
    event RelayedMsgFailed(bytes32 indexed hash, uint256 nonce);

    event RollingHash(bytes32 indexed hash);

    event AppendMsg(uint256 index, bytes32 messageHash);

    function pause() external;

    function unpause() external;

    /**
     * send mg to target chain;
     * @param target_; target chain bridge contract address
     * @param value_; native token transfer value
     * @param msg_; msg send to target chain
     * @param gasLimit_; gaslimit on target chain
     * @param refundAddress_; refund address after value and gaslimit
     */
    function sendMsg(
        address target_,
        uint256 value_,
        bytes calldata msg_,
        uint256 gasLimit_,
        address refundAddress_
    ) external payable;
}
