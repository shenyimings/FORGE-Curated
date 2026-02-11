// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IL1BridgeProof.sol";

interface IL1ETHBridge {
    /**
     * @notice Deposit event
     * @param from; L1 withdrawer account address
     * @param to; L2 Receiver account address
     * @param amount; assert amount
     * @param msg; none
     */
    event DepositETH(address indexed from, address indexed to, uint256 amount, bytes msg);

    /**
     * @notice Withdraw event
     * @param from; L2 withdrawer account address
     * @param to; L1 receiver account address
     * @param amount; assert amount
     * @param msg; none
     */
    event FinalizeWithdrawETH(address indexed from, address indexed to, uint256 amount, bytes msg);

    /**
     * The sender account transfers funds to TokenBridge to lock the assets;
     * @param to_; L2 Receiver account address
     * @param amount_; assert amount
     * @param gasLimit_; gas limit on l2
     * @param data_; none
     */
    function deposit(address to_, uint256 amount_, uint256 gasLimit_, bytes memory data_) external payable;

    /**
     * Access the rollup contract to obtain the message tree root of the corresponding batch, and after verifying the proof, execute the corresponding asset transfer;
     * @param sender_ Withdrawer account address
     * @param to_ L1 recipient account address
     * @param value_ Asset quantity
     * @param msg_; none
     */
    function finalizeWithdraw(address sender_, address to_, uint256 value_, bytes memory msg_) external payable;
}
