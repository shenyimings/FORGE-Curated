// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CommonBase } from "forge-std/Base.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/Executor.sol";

import { MockSwap } from "../mocks/MockSwap.sol";

contract SwapActionsBuilder is CommonBase {
    MockSwap internal mockSwap;

    constructor(address _swapRouter) {
        mockSwap = MockSwap(_swapRouter);
    }

    // Each token `tokens[i]` gets swapped into `outputTokens[i]`
    function buildSwapActions(
        address[] memory tokens,
        uint256[] memory amounts,
        address[] memory outputTokens,
        address[] memory recipients
    )
        public
        view
        returns (Action[] memory)
    {
        Action[] memory actions = new Action[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            actions[i].to = address(mockSwap);
            actions[i].data =
                abi.encodeCall(MockSwap.swapToRecipient, (tokens[i], outputTokens[i], amounts[i], recipients[i]));
        }

        return actions;
    }

    // Every token is swapped into single `outputToken`.
    function buildSwapActions(
        address[] memory tokens,
        uint256[] memory amounts,
        address outputToken,
        address recipient
    )
        public
        view
        returns (Action[] memory)
    {
        address[] memory outTokens = new address[](tokens.length);
        address[] memory recipients = new address[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            outTokens[i] = outputToken;
            recipients[i] = recipient;
        }

        return buildSwapActions(tokens, amounts, outTokens, recipients);
    }
}
