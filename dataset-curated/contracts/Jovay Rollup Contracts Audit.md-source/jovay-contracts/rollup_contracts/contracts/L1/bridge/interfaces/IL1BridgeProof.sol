// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IL1Mailbox} from "../../interfaces/IL1Mailbox.sol";

interface IL1BridgeProof {
    function relayMsgWithProof(
        uint256 value_,
        uint256 nonce_,
        bytes memory msg_,
        IL1Mailbox.L2MsgProof memory proof_
    ) external payable;
}
