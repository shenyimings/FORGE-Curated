// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../common/interfaces/IMailBoxBase.sol";

interface IL2Mailbox is IMailBoxBase {
    /**
     * Send L1 message to current L2 through Relayer, and execute the corresponding message in L2 bridge contract
     * @param sender_ sender L1 bridge contract address
     * @param target_ message receiver current L2 bridge contract address
     * @param value_ native token transfer amount
     * @param nonce_ message nonce value
     * @param msg_ message content sent to target_ for execution
     */
    function relayMsg(
        address sender_,
        address target_,
        uint256 value_,
        uint256 nonce_,
        bytes calldata msg_
    ) external;

    function claimAmount(
        address refundAddress,
        uint256 amount,
        uint256 nonce_,
        bytes32 msgHash_
    ) external;
}
