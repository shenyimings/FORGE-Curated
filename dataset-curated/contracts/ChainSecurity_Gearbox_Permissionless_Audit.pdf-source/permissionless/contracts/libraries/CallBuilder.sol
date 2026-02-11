// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Call} from "../interfaces/Types.sol";

library CallBuilder {
    function build() internal pure returns (Call[] memory calls) {}

    function build(Call memory call1) internal pure returns (Call[] memory calls) {
        calls = new Call[](1);
        calls[0] = call1;
    }

    function build(Call memory call1, Call memory call2) internal pure returns (Call[] memory calls) {
        calls = new Call[](2);
        calls[0] = call1;
        calls[1] = call2;
    }

    function build(Call memory call1, Call memory call2, Call memory call3)
        internal
        pure
        returns (Call[] memory calls)
    {
        calls = new Call[](3);
        calls[0] = call1;
        calls[1] = call2;
        calls[2] = call3;
    }

    function build(Call memory call1, Call memory call2, Call memory call3, Call memory call4)
        internal
        pure
        returns (Call[] memory calls)
    {
        calls = new Call[](4);
        calls[0] = call1;
        calls[1] = call2;
        calls[2] = call3;
        calls[3] = call4;
    }

    function build(Call memory call1, Call memory call2, Call memory call3, Call memory call4, Call memory call5)
        internal
        pure
        returns (Call[] memory calls)
    {
        calls = new Call[](5);
        calls[0] = call1;
        calls[1] = call2;
        calls[2] = call3;
        calls[3] = call4;
        calls[4] = call5;
    }

    function build(
        Call memory call1,
        Call memory call2,
        Call memory call3,
        Call memory call4,
        Call memory call5,
        Call memory call6
    ) internal pure returns (Call[] memory calls) {
        calls = new Call[](6);
        calls[0] = call1;
        calls[1] = call2;
        calls[2] = call3;
        calls[3] = call4;
        calls[4] = call5;
        calls[5] = call6;
    }

    function append(Call[] memory calls, Call memory call) internal pure returns (Call[] memory newCalls) {
        uint256 numCalls = calls.length;
        newCalls = new Call[](numCalls + 1);
        for (uint256 i; i < numCalls; ++i) {
            newCalls[i] = calls[i];
        }
        newCalls[numCalls] = call;
    }

    function extend(Call[] memory calls1, Call[] memory calls2) internal pure returns (Call[] memory newCalls) {
        uint256 num1 = calls1.length;
        uint256 num2 = calls2.length;
        newCalls = new Call[](num1 + num2);
        for (uint256 i; i < num1; ++i) {
            newCalls[i] = calls1[i];
        }
        for (uint256 i; i < num2; ++i) {
            newCalls[num1 + i] = calls2[i];
        }
    }
}
