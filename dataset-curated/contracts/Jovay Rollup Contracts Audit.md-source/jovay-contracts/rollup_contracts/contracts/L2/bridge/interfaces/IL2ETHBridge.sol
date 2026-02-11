// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IL2ETHBridge {
    /**
     * Withdrawal event
     * @param from transfer initiator
     * @param to target address
     * @param amount transfer amount
     * @param msg data
     */
    event WithdrawETH(address indexed from, address indexed to, uint256 amount, bytes msg);

    /**
     * Complete the transfer of L1 assets
     * @param from transfer initiator
     * @param to target address
     * @param amount transfer amount
     * @param msg data
     */
    event FinalizeDepositETH(address indexed from, address indexed to, uint256 amount, bytes msg);

    /**
     * The sender account transfers to tokenbridge to lock the assets;
     * @param to_ target address
     * @param amount_ transfer amount
     * @param gasLimit_ gas limit
     * @param data_ data
     */
    function withdraw(address to_, uint256 amount_, uint256 gasLimit_, bytes memory data_) external payable;

    /**
     * Complete the transfer of L1 assets
     * @param sender_ transfer initiator
     * @param to_ target address
     * @param amount_ transfer amount
     * @param data_ data
     */
    function finalizeDeposit(address sender_, address to_, uint256 amount_, bytes calldata data_) external payable;

    function claimDeposit(bytes calldata msg_) external;
    function claimDeposit(bytes calldata msg_, address new_refund_address_) external;
}
