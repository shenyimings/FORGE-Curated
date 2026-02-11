// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../common/interfaces/IMailBoxBase.sol";

interface IL1Mailbox is IMailBoxBase {
    struct L2MsgProof {
        uint256 batchIndex;
        bytes merkleProof;
    }

    /**
     * Send L2 message to L1, need to verify the validity of the message through proof,
     * if valid, execute the corresponding message in L1 bridge contract
     * @param sender_ sender L2 bridge contract address
     * @param target_ message receiver current L1 bridge contract address
     * @param value_ native token transfer amount
     * @param nonce_ message nonce value
     * @param msg_ message content sent to target_ execution
     * @param proof_ proof information used to prove the validity of the message
     */
    function relayMsgWithProof(
        address sender_,
        address target_,
        uint256 value_,
        uint256 nonce_,
        bytes memory msg_,
        L2MsgProof memory proof_
    ) external payable;
}
