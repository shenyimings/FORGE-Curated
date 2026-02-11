// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../L1/bridge/interfaces/IL1ETHBridge.sol";
import "../../common/BridgeBase.sol";
import "../interfaces/IL2Mailbox.sol";
import "./interfaces/IL2ETHBridge.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";
import {L2Mailbox} from "../core/L2Mailbox.sol";

contract L2ETHBridge is BridgeBase, IL2ETHBridge {
    uint256 public balance;

    /**
     * The sender account transfers to tokenbridge to lock the assets;
     * @param to_ target address
     * @param amount_ transfer amount
     * @param gasLimit_ gas limit
     * @param msg_ data
     */
    function withdraw(address to_, uint256 amount_, uint256 gasLimit_, bytes memory msg_) external payable override nonReentrant whenNotPaused {
        require(msg.value > 0, "withdraw zero eth");
        require(balance >= amount_, "insufficient balance");

        address sender_ = _msgSender();

        bytes memory message_ = abi.encodeCall(IL1ETHBridge.finalizeWithdraw, (sender_, to_, amount_, msg_));
        balance -= amount_;
        mailBoxCall(abi.encodeCall(IMailBoxBase.sendMsg, (toBridge, amount_, message_, gasLimit_, sender_)));
        emit WithdrawETH(sender_, to_, amount_, message_);
    }


    /**
     * Complete the transfer of L1 assets
     * @param sender_ transfer initiator
     * @param to_ target address
     * @param amount_ transfer amount
     * @param msg_ data
     */
    function finalizeDeposit(address sender_, address to_, uint256 amount_, bytes calldata msg_) external payable override nonReentrant onlyMailBox whenNotPaused {
        require(msg.value == amount_, "msg.value mismatch");
        balance += amount_;

        (bool success_,) = to_.call{value : amount_, gas : gasleft() / 2}("");
        require(success_, "ETH transfer failed");
// TODO : add call msg with deposit
//        _doCallback(to_, msg_);

        emit FinalizeDepositETH(sender_, to_, amount_, msg_);
    }

    function claimDeposit(bytes calldata msg_) external override nonReentrant whenNotPaused {
        (address l1bridge, address l2bridge, uint256 value, uint256 nonce, bytes memory depositMsg) = abi.decode(msg_[4:], (address, address, uint256, uint256, bytes));
        bytes memory newDepositMsg = BytesLib.slice(depositMsg, 4, depositMsg.length-4);
        (address sender, address target, uint256 amount, bytes memory data) = abi.decode(newDepositMsg, (address, address, uint256, bytes));
        bytes32 depositHash = keccak256(msg_);
        balance += amount;
        IL2Mailbox(mailBox).claimAmount(target, amount, nonce,depositHash);
    }

    function claimDeposit(bytes calldata msg_, address new_refund_address_) external override nonReentrant whenNotPaused {
        (address l1bridge, address l2bridge, uint256 value, uint256 nonce, bytes memory depositMsg) = abi.decode(msg_[4:], (address, address, uint256, uint256, bytes));
        bytes memory newDepositMsg = BytesLib.slice(depositMsg, 4, depositMsg.length-4);
        (address sender, address target, uint256 amount, bytes memory data) = abi.decode(newDepositMsg, (address, address, uint256, bytes));
        bytes32 depositHash = keccak256(msg_);
        balance += amount;
        require(msg.sender == sender, "claimDeposit change refund must called by origin sender");
        IL2Mailbox(mailBox).claimAmount(new_refund_address_, amount, nonce, depositHash);
    }
}
