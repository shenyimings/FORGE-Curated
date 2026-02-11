// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2025 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.22;

import { IGovernanceOAppSender, MessagingFee, TxParams } from "lib/sky-oapp-oft/contracts/interfaces/IGovernanceOAppSender.sol";

// Note: we assume that if used, the LZ token is examined to be standard and revert on failure
interface TokenLike {
    function approve(address spender, uint256 amount) external;
    function transfer(address recipient, uint256 amount) external;
}

interface L2GovernanceRelayLike {
    function relay(address target, bytes calldata targetData) external;
}

contract L1GovernanceRelay {
    // --- storage variables ---

    mapping(address => uint256) public wards;
    TokenLike                   public lzToken;
    IGovernanceOAppSender       public l1Oapp;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "L1GovernanceRelay/not-authorized");
        _;
    }

    // --- constructor ---

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- administration ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, address data) external auth {
        if      (what == "lzToken") lzToken = TokenLike(data);
        else if (what == "l1Oapp")  l1Oapp  = IGovernanceOAppSender(data);
        else revert("L1GovernanceRelay/file-unrecognized-param");
        emit File(what, data);
    }

    // --- logic ---

    receive() external payable {}

    function reclaim(address receiver, uint256 amount) external auth {
        (bool sent, ) = receiver.call{value: amount}("");
        require(sent, "L1GovernanceRelay/failed-to-send-ether");
    }

    function reclaimLzToken(address receiver, uint256 amount) external auth {
        lzToken.transfer(receiver, amount);
    }

    // Notes:
    // It is not likely that lzTokenFee is used, support is added here just for completeness.
    // In case it is used, governance is assumed to monitor LZ for token changes.
    // If deemed needed, this includes a check in the spell itself and fallback code.
    // Also assuming that the send library is configured explicitly, so any default behavior is not relied on (as can change).
    // Also assuming that if authed to multiple senders, they are trusted not to steal/waste eth/tokens from each other.
    // (dstEid, dstTarget) is assumed to be whitelisted in the l1 Oapp for this src sender.

    function relayEVM(
        uint32                dstEid,
        address               l2GovernanceRelay,
        address               target,
        bytes calldata        targetData,
        bytes calldata        extraOptions,
        MessagingFee calldata fee,
        address               refundAddress
    ) external payable auth {
        TxParams memory txParams = TxParams({
            dstEid       : dstEid,
            dstTarget    : bytes32(uint256(uint160(address(l2GovernanceRelay)))),
            dstCallData  : abi.encodeCall(L2GovernanceRelayLike.relay, (target, targetData)),
            extraOptions : extraOptions
        });
        _send(txParams, fee, refundAddress);
    }

    function relayRaw(
        TxParams calldata     txParams,
        MessagingFee calldata fee,
        address               refundAddress
    ) external payable auth {
        _send(txParams, fee, refundAddress);
    }

    function _send(
        TxParams memory       txParams,
        MessagingFee calldata fee,
        address               refundAddress
    ) internal {
        if (fee.lzTokenFee > 0) lzToken.approve(address(l1Oapp), fee.lzTokenFee);
        l1Oapp.sendTx{value: fee.nativeFee}(txParams, fee, refundAddress);
    }
}
