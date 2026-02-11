// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

contract MultiCall {
    struct Call {
        address target;
        bytes data;
        uint256 gasLimit;
        uint256 value;
        bool revertOnError;
    }

    error NotEnoughGas(uint256 index, uint256 requested, uint256 available);
    error CallReverted(uint256 index, bytes result);

    function multiCall(
        Call[] calldata _calls
    ) public payable virtual returns (bool[] memory successes, bytes[] memory results) {
        successes = new bool[](_calls.length);
        results = new bytes[](_calls.length);

        for (uint256 i = 0; i < _calls.length; i++) {
            Call calldata call = _calls[i];

            if (gasleft() < call.gasLimit) revert NotEnoughGas(i, call.gasLimit, gasleft());

            (successes[i], results[i]) = call.target.call{
                value: call.value,
                gas: call.gasLimit == 0 ? gasleft() : call.gasLimit
            }(call.data);

            if (!successes[i] && _calls[i].revertOnError) revert CallReverted(i, results[i]);
        }

        if (address(this).balance > 0) {
            Transfer.native(msg.sender, address(this).balance);
        }
    }
}
