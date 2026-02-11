// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./interfaces/IL2ERC20Bridge.sol";
import "../interfaces/IL2Mailbox.sol";
import "../../common/TokenBridge.sol";
import "../../common/interfaces/IERC20Token.sol";
import "../../L1/bridge/interfaces/IL1ERC20Bridge.sol";

contract L2ERC20Bridge is TokenBridge, IL2ERC20Bridge {
    /**
     * Set token mapping relationship
     * @param token_ Current chain asset contract address
     * @param tokenTo_ Target asset contract address
     */
    function setTokenMapping(address token_, address tokenTo_) public payable override onlyOwner whenNotPaused {
        super.setTokenMapping(token_, tokenTo_);
    }

    /**
     * The bridge contract calls the asset contract to burn the asset and sends a message to the mailbox contract to build a message tree
     * @param token_ erc20 contract address
     * @param to_ target address
     * @param amount_ transfer amount
     * @param gasLimit_ gas limit
     * @param msg_ data
     */
    function withdraw(address token_, address to_, uint256 amount_, uint256 gasLimit_, bytes memory msg_) external payable override nonReentrant whenNotPaused {
        address l1Token_ = tokenMapping[token_];
        require(l1Token_ != address(0), "withdraw erc20 token not exist");

        require(amount_ > 0, "withdraw zero amount");

        // 1. Extract real sender if this call is from L2GatewayRouter.
        address sender_ = _msgSender();

        // 2. Burn token.
        IERC20Token(token_).burn(sender_, amount_);

        // 3. Generate message passed to IL1ERC20Bridge.
        bytes memory message_ = abi.encodeCall(
            IL1ERC20Bridge.finalizeWithdraw,
            (l1Token_, token_, sender_, to_, amount_, msg_)
        );

        // 4. send message to L2Mailbox
        mailBoxCall(abi.encodeCall(IMailBoxBase.sendMsg, (toBridge, amount_, message_, gasLimit_, sender_)));

        emit WithdrawERC20(l1Token_, token_, sender_, to_, amount_, message_);
        _decreaseBalance(token_, amount_);
        require(IERC20Token(token_).totalSupply() == balanceOf[token_], "totalSupply mismatch");
    }

    /**
     * Complete the transfer of L1 assets
     * @param l1Token_ L1 chain asset contract address
     * @param l2Token_ L2 chain asset contract address
     * @param sender_ transfer initiator
     * @param to_ target address
     * @param amount_ transfer amount
     * @param msg_ data
     */
    function finalizeDeposit(address l1Token_, address l2Token_, address sender_, address to_, uint256 amount_, bytes calldata msg_) external payable override nonReentrant onlyMailBox whenNotPaused {
        require(msg.value == 0, "nonzero msg.value");
        require(l1Token_ != address(0), "token address cannot be 0");
        require(l1Token_ == tokenMapping[l2Token_], "l1 token mismatch");

        IERC20Token(l2Token_).mint(to_, amount_);
        _increaseBalance(l2Token_, amount_);
        // TODO : add call msg with deposit
//        _doCallback(to_, msg_);
        require(IERC20Token(l2Token_).totalSupply() == balanceOf[l2Token_], "totalSupply mismatch");

        emit FinalizeDepositERC20(l1Token_, l2Token_, sender_, to_, amount_, msg_);
    }
}
