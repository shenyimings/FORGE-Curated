// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IL1ERC20Bridge.sol";
import "../interfaces/IL1Mailbox.sol";
import "../../L2/bridge/interfaces/IL2ERC20Bridge.sol";
import "../../common/TokenBridge.sol";
import {L1BridgeProof} from "src/L1/bridge/L1BridgeProof.sol";

contract L1ERC20Bridge is TokenBridge, L1BridgeProof, IL1ERC20Bridge {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * Set token mapping relationship
     * @param token_ this chain asset contract address
     * @param tokenTo_ Target chain asset contract address
     */
    function setTokenMapping(address token_, address tokenTo_) public override payable onlyOwner whenNotPaused {
        require(token_ != address(0) && tokenTo_ != address(0), "token address cannot be 0");

        super.setTokenMapping(token_, tokenTo_);

        // update corresponding mapping in L2, 1000000 gas limit should be enough
        bytes memory message_ = abi.encodeCall(ITokenBridge.setTokenMapping, (tokenTo_, token_));
        mailBoxCall(abi.encodeCall(IMailBoxBase.sendMsg, (toBridge, 0, message_, 1000000, _msgSender())));
    }

    function deposit(address token_, address to_, uint256 amount_, uint256 gasLimit_, bytes memory msg_) external override payable nonReentrant whenNotPaused {
        address l2Token_ = tokenMapping[token_];
        require(l2Token_ != address(0), "deposit erc20 token not exist");

        // 1. Transfer token into this contract.
        address sender_ = _msgSender();
        _transferERC20(token_, amount_);

        // 2. Generate message passed to L2CustomERC20Gateway.
        bytes memory message_ = abi.encodeCall(IL2ERC20Bridge.finalizeDeposit, (token_, l2Token_, sender_, to_, amount_, msg_));

        // 3. Send message to L1Mailbox.
        mailBoxCall(abi.encodeCall(IMailBoxBase.sendMsg, (toBridge, 0, message_, gasLimit_, sender_)));

        emit DepositERC20(token_, l2Token_, sender_, to_, amount_, msg_);
    }

    function finalizeWithdraw(address l1Token_, address l2Token_, address sender_, address to_, uint256 amount_, bytes memory msg_) external payable override nonReentrant onlyMailBox whenNotPaused {
        require(l2Token_ == tokenMapping[l1Token_], "l2 token not exist");
        IERC20Upgradeable(l1Token_).safeTransfer(to_, amount_);
        _decreaseBalance(l1Token_, amount_);
        // TODO : add call msg with withdraw
//        _doCallback(to_, msg_);
        require(IERC20Upgradeable(l1Token_).balanceOf(address(this)) >= balanceOf[l1Token_], "totalSupply mismatch");

        emit FinalizeWithdrawERC20(l1Token_, l2Token_, sender_, to_, amount_, msg_);
    }

    function _transferERC20(address token_, uint256 amount_) internal {
        require(amount_ > 0, "deposit zero amount");
        address sender_ = _msgSender();
        // common practice to handle fee on transfer token.
        IERC20Upgradeable(token_).safeTransferFrom(sender_, address(this), amount_);
        _increaseBalance(token_, amount_);
        require(IERC20Upgradeable(token_).balanceOf(address(this)) >= balanceOf[token_], "balance not match");
    }
}
