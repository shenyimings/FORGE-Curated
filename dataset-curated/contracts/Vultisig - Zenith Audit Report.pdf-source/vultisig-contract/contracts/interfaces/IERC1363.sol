// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC1363
 * @dev Interface of the ERC-1363 standard as defined in the https://eips.ethereum.org/EIPS/eip-1363[ERC-1363].
 *
 * An extension interface for ERC-20 tokens that supports executing code on a recipient contract after `transfer` or `transferFrom`, or code on a spender contract after `approve`, in a single transaction.
 */
interface IERC1363 {
    /**
     * @dev Indicates a failure with the token `receiver` as it can't be an EOA. Used in transfers.
     * @param receiver The address to which tokens are being transferred.
     */
    error ERC1363EOAReceiver(address receiver);

    /**
     * @dev Indicates a failure with the token `spender` as it can't be an EOA. Used in approvals.
     * @param spender The address which will spend the funds.
     */
    error ERC1363EOASpender(address spender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver The address to which tokens are being transferred.
     */
    error ERC1363InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the token `spender`. Used in approvals.
     * @param spender The address which will spend the funds.
     */
    error ERC1363InvalidSpender(address spender);

    /**
     * @dev Indicates a failure with the ERC-20 `transfer` during a `transferAndCall` operation. Used in transfers.
     * @param receiver The address to which tokens are being transferred.
     * @param value The amount of tokens to be transferred.
     */
    error ERC1363TransferFailed(address receiver, uint256 value);

    /**
     * @dev Indicates a failure with the ERC-20 `transferFrom` during a `transferFromAndCall` operation. Used in transfers.
     * @param sender The address from which to send tokens.
     * @param receiver The address to which tokens are being transferred.
     * @param value The amount of tokens to be transferred.
     */
    error ERC1363TransferFromFailed(address sender, address receiver, uint256 value);

    /**
     * @dev Indicates a failure with the ERC-20 `approve` during a `approveAndCall` operation. Used in approvals.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     */
    error ERC1363ApproveFailed(address spender, uint256 value);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to` and then calls `IERC1363Receiver::onTransferReceived` on `to`.
     * @param to The address to which tokens are being transferred.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to` and then calls `IERC1363Receiver::onTransferReceived` on `to`.
     * @param to The address to which tokens are being transferred.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism and then calls `IERC1363Receiver::onTransferReceived` on `to`.
     * @param from The address from which to send tokens.
     * @param to The address to which tokens are being transferred.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism and then calls `IERC1363Receiver::onTransferReceived` on `to`.
     * @param from The address from which to send tokens.
     * @param to The address to which tokens are being transferred.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value, bytes calldata data)
        external
        returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the caller's tokens and then calls `IERC1363Spender::onApprovalReceived` on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @return A boolean value indicating the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the caller's tokens and then calls `IERC1363Spender::onApprovalReceived` on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @param data Additional data with no specified format, sent in call to `spender`.
     * @return A boolean value indicating the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);
}
