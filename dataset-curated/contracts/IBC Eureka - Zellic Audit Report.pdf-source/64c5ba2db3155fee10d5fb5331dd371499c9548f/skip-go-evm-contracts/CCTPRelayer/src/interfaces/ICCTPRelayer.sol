// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @dev Interface for Skip CCTPRelayer contract.
 */
interface ICCTPRelayer {
    error ZeroAddress();
    error TransferFailed();
    error ETHSendFailed();
    error MissingBalance();
    error PaymentCannotBeZero();
    error SwapFailed();
    error InsufficientSwapOutput();
    error InsufficientNativeToken();
    error Reentrancy();

    event PaymentForRelay(uint64 nonce, uint256 paymentAmount);

    event FailedReceiveMessage(bytes message, bytes attestation);

    struct ReceiveCall {
        bytes message;
        bytes attestation;
    }

    function makePaymentForRelay(uint64 nonce, uint256 paymentAmount) external;

    function requestCCTPTransfer(
        uint256 transferAmount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        uint256 feeAmount
    ) external;
}
