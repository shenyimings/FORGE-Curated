// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./interfaces/IL1ETHBridge.sol";
import "../interfaces/IL1Mailbox.sol";
import "../../L2/bridge/interfaces/IL2ETHBridge.sol";
import "./L1BridgeProof.sol";

contract L1ETHBridge is L1BridgeProof, IL1ETHBridge {
    using AddressUpgradeable for address;
    uint256 public balance;

    function deposit(address to_, uint256 amount_, uint256 gasLimit_, bytes memory msg_) external payable override nonReentrant whenNotPaused {
        require(amount_ > 0, "deposit zero eth");
        // 1. Extract real sender if this call is from L1GatewayRouter.
        address sender_ = _msgSender();

        // 2. Generate message passed to L1Mailbox.
        bytes memory message_ = abi.encodeCall(IL2ETHBridge.finalizeDeposit, (sender_, to_, amount_, msg_));
        balance += amount_;
        mailBoxCall(abi.encodeCall(IMailBoxBase.sendMsg, (toBridge, amount_, message_, gasLimit_, sender_)));

        emit DepositETH(sender_, to_, amount_, msg_);
    }

    function finalizeWithdraw(address sender_, address to_, uint256 amount_, bytes memory msg_) external payable override nonReentrant onlyMailBox whenNotPaused {
        require(msg.value == amount_, "msg.value mismatch");
        require(balance >= amount_, "balance too low");

        // @note can possible trigger reentrant call to messenger,
        // but it seems not a big problem.
        balance -= amount_;
        (bool success_, ) = to_.call{value: amount_}("");
        require(success_, "ETH transfer failed");
// TODO : add call msg with withdraw
//        _doCallback(to_, msg_);

        emit FinalizeWithdrawETH(sender_, to_, amount_, msg_);
    }
}
