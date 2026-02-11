// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|                           
*/

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ReferralSigning {
    using ECDSA for bytes32;

    // ----------- STORAGE ------------
    mapping(address referredBy => mapping(address user => bool wasReferred)) public referredByRegistry;
    mapping(address user => address referredBy) public referralsForUserRegistry;
    mapping(address referredBy => address[] users) public referralRegistry;
    mapping(address referredBy => uint256 total) public totalReferred;
    mapping(address user => bool wasReferred) public isUserReferred;
    mapping(address user => uint256 nonce) public nonces;

    // ----------- EVENTS ------------
    event ReferralClaimed(address indexed referred, address indexed referrer);
    event ReferralRejected(address indexed referred, address indexed referrer, string reason);

    // ----------- ERRORS ------------
    error ReferralSigning_SameUser();
    error ReferralSigning_InvalidSignature();
    error ReferralSigning_UserAlreadyReferred();
    error ReferralSigning_ContractReferrerNotAllowed();

    // ----------- MODIFIERS ------------
    modifier onlyNewUser() {
        if (isUserReferred[msg.sender]) {
            emit ReferralRejected(msg.sender, msg.sender, "Already referred");
            revert ReferralSigning_UserAlreadyReferred();
        }
        _;
    }

    // ----------- PUBLIC ------------
    function claimReferral(bytes calldata signature, address referrer) external onlyNewUser {
        if (msg.sender == referrer) {
            emit ReferralRejected(msg.sender, referrer, "Self-referral not allowed");
            revert ReferralSigning_SameUser();
        }

        if (referrer.code.length != 0) {
            emit ReferralRejected(msg.sender, referrer, "Contract referrers not allowed");
            revert ReferralSigning_ContractReferrerNotAllowed();
        }

        bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, referrer, nonces[msg.sender]));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);

        address signer = ethSignedMessageHash.recover(signature);
        if (signer != msg.sender) {
            emit ReferralRejected(msg.sender, referrer, "Invalid signature");
            revert ReferralSigning_InvalidSignature();
        }

        referredByRegistry[referrer][msg.sender] = true;
        referralsForUserRegistry[msg.sender] = referrer;
        referralRegistry[referrer].push(msg.sender);
        totalReferred[referrer]++;
        isUserReferred[msg.sender] = true;
        nonces[msg.sender]++;

        emit ReferralClaimed(msg.sender, referrer);
    }
}
