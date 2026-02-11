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

import { GemMock } from "test/mocks/GemMock.sol";
import { MessagingFee, MessagingReceipt, TxParams } from "lib/sky-oapp-oft/contracts/interfaces/IGovernanceOAppSender.sol";

contract OappSenderMock {
    GemMock public lzToken;

    event SentMessageEVM(
        uint32 dstEid,
        bytes32 dstTarget,
        bytes dstCallData,
        bytes extraOptions,
        uint256 nativeFee,
        uint256 lzTokenFee,
        address refundAddress
    );

    constructor(address _lzToken) {
        lzToken = GemMock(_lzToken);
    }

    function sendTx(
        TxParams calldata _params,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory receipt) {
        receipt; // avoid compilation warning

        require(msg.value == _fee.nativeFee, "OappMock/NotEnoughNative");
        if (_fee.lzTokenFee > 0) lzToken.transferFrom(msg.sender, address(this), _fee.lzTokenFee); // transfer here instead of the endpoint

        emit SentMessageEVM(
            _params.dstEid,
            _params.dstTarget,
            _params.dstCallData,
            _params.extraOptions,
            _fee.nativeFee,
            _fee.lzTokenFee,
            _refundAddress
        );

        // This should actually happen on the receiving chain, but added here for testing purposes
        (bool success, bytes memory returnData) = address(uint160(uint256(_params.dstTarget))).call{value: 0}(_params.dstCallData); // assume value is 0
        if (!success) {
            if (returnData.length == 0) revert("OappMock/length-error");
            assembly ("memory-safe") {
                revert(add(32, returnData), mload(returnData))
            }
        }
    }
}
