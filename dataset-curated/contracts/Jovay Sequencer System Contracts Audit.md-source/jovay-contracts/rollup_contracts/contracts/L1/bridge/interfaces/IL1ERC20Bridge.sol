// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IL1BridgeProof.sol";
import "../../../common/interfaces/ITokenBridge.sol";

interface IL1ERC20Bridge {
    /***
     * DepositERC20 transfer from l1 to l2
     * @param l1token; token address on l1
     * @param l2token; token address on l2
     * @param from; sender address on l1
     * @param to; receiver address on l2
     * @param amount; transfer amount
     * @param data; none
     */
    event DepositERC20(
        address l1token,
        address l2token,
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes data
    );

    /**
     * WithdrawERC20 transfer from l2 to l1
     * @param l1Token; token address on l1
     * @param l2Token; token address on l2
     * @param from; withdraw address on l2
     * @param to; receiver address on l1
     * @param amount; transfer amount
     * @param data; none
     */
    event FinalizeWithdrawERC20(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes data
    );

    /**
     * The user specifies the asset contract, and the bridge contract locks the asset;
     * @param token_; token address on l1
     * @param to_; receiver address on l2
     * @param amount_; asset amount
     * @param gasLimit_; gaslimit on l2
     * @param data_; none
     */
    function deposit(address token_, address to_, uint256 amount_, uint256 gasLimit_, bytes memory data_) external payable;

    /**
     * call the rollup contract to obtain the l2 message tree root of
     * the corresponding batch, verify the proof and execute the corresponding asset transfer;
     * @param l1Token_; token address on l1
     * @param l2Token_; token address on l2
     * @param sender_;  withdraw address on l2
     * @param to_; receiver address on l1
     * @param amount_; asset amount
     * @param msg_; none
     */
    function finalizeWithdraw(address l1Token_, address l2Token_, address sender_, address to_, uint256 amount_, bytes memory msg_) external payable;
}
