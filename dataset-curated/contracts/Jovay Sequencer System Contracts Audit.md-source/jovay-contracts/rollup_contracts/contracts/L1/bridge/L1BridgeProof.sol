// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../common/BridgeBase.sol";
import "./interfaces/IL1BridgeProof.sol";

contract L1BridgeProof is BridgeBase, IL1BridgeProof {
    function relayMsgWithProof(
        uint256 value_,
        uint256 nonce_,
        bytes memory msg_,
        IL1Mailbox.L2MsgProof memory proof_
    ) external payable whenNotPaused {
        mailBoxCall(abi.encodeCall(IL1Mailbox.relayMsgWithProof, (toBridge, address(this), value_, nonce_, msg_, proof_)));
    }
}
