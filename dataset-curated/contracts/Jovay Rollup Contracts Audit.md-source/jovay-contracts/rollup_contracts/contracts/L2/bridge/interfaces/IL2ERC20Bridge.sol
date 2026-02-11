// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IL2ERC20Bridge {
    /**
     * @notice WithdrawERC20 event
     * @param l1Token L1 chain asset contract address
     * @param l2Token L2 chain asset contract address
     * @param from L2 transfer initiator
     * @param to L1 target address
     * @param amount transfer amount
     * @param data optional execution data passed to L1 to address
     */
    event WithdrawERC20(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes data
    );

    /**
     * @notice DepositERC20 event
     * @param l1Token L1 chain asset contract address
     * @param l2Token L2 chain asset contract address
     * @param from L1 transfer initiator
     * @param to L2 target address
     * @param amount transfer amount
     * @param msg optional execution data passed to L2 to address
     */
    event FinalizeDepositERC20(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes msg
    );

    /**
     * The bridge contract calls the asset contract to burn the asset and sends a message to the mailbox contract to build a message tree
     * @param token_ erc20 contract address
     * @param to_ target address
     * @param amount_ transfer amount
     * @param gasLimit_ gas limit
     * @param msg_ data
     */
    function withdraw(address token_, address to_, uint256 amount_, uint256 gasLimit_, bytes memory msg_) external payable;

    /**
     * Complete the transfer of L1 assets
     * @param l1Token_ L1 chain asset contract address
     * @param l2Token_ L2 chain asset contract address
     * @param sender_ transfer initiator
     * @param to_ target address
     * @param amount_ transfer amount
     * @param msg_ data
     */
    function finalizeDeposit(address l1Token_, address l2Token_, address sender_, address to_, uint256 amount_, bytes calldata msg_) external payable;
}
