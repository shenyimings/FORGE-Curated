// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IICS20TransferMsgs {
    /// @notice Message for sending a transfer
    /// @param denom The address of the ERC20 token contract, used as the denomination
    /// @param amount The amount of tokens to transfer
    /// @param receiver The receiver of the transfer on the counterparty chain
    /// @param sourceClient The source client identifier
    /// @param destPort The destination port on the counterparty chain
    /// @param timeoutTimestamp The absolute timeout timestamp in unix seconds
    /// @param memo Optional memo
    struct SendTransferMsg {
        address denom;
        uint256 amount;
        string receiver;
        string sourceClient;
        string destPort;
        uint64 timeoutTimestamp;
        string memo;
    }
}

interface IICS20Transfer {
    /// @notice Send a transfer by constructing a message and calling IICS26Router.sendPacket
    /// @param msg_ The message for sending a transfer
    /// @return sequence The sequence number of the packet created
    function sendTransfer(IICS20TransferMsgs.SendTransferMsg calldata msg_) external returns (uint32 sequence);

    /// @notice Send a transfer by constructing a message and calling IICS26Router.sendPacket with the provided sender
    /// @dev This is a permissioned function requiring the `DELEGATE_SENDER_ROLE`
    /// @dev Useful for contracts that need to refund the tokens to a sender.
    /// @param msg_ The message for sending a transfer
    /// @param sender The sender of the transfer
    /// @return sequence The sequence number of the packet created
    function sendTransferWithSender(IICS20TransferMsgs.SendTransferMsg calldata msg_, address sender)
        external
        returns (uint32 sequence);
}
