// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IL1MailQueue {

    event PopMsgs(uint256 finalizeMsgIndex);

    /**
     * @notice Returns next message index
     */
    function nextMsgIndex() external view returns (uint256);

    /**
     * @dev Returns the message at the given index.
     * @param _index The index of the message to be returned.
     */
    function getMsg(uint256 _index) external view returns (bytes32);

    /// @notice Emitted when a batch is verified.
    /// @param _l1MsgIndex The index of the batch.
    function popMsgs(uint256 _l1MsgIndex) external;
}
