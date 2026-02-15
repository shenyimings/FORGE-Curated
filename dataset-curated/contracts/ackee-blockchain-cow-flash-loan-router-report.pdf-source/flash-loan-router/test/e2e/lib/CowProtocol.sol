// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {ICowSettlement} from "src/interface/ICowSettlement.sol";

import {Constants} from "./Constants.sol";

library CowProtocol {
    function addSolver(Vm vm, address solver) internal {
        vm.prank(Constants.AUTHENTICATOR_MANAGER);
        Constants.SOLVER_AUTHENTICATOR.addSolver(solver);
    }

    function emptySettleWithInteractions(ICowSettlement.Interaction[] memory intraInteractions) internal {
        (
            address[] memory noTokens,
            uint256[] memory noPrices,
            ICowSettlement.Trade[] memory noTrades,
            ICowSettlement.Interaction[][3] memory interactions
        ) = emptySettleInputWithInteractions(intraInteractions);

        Constants.SETTLEMENT_CONTRACT.settle(noTokens, noPrices, noTrades, interactions);
    }

    function encodeEmptySettleWithInteractions(ICowSettlement.Interaction[] memory intraInteractions)
        internal
        pure
        returns (bytes memory)
    {
        (
            address[] memory noTokens,
            uint256[] memory noPrices,
            ICowSettlement.Trade[] memory noTrades,
            ICowSettlement.Interaction[][3] memory interactions
        ) = emptySettleInputWithInteractions(intraInteractions);

        return abi.encodeCall(ICowSettlement.settle, (noTokens, noPrices, noTrades, interactions));
    }

    function emptySettleInputWithInteractions(ICowSettlement.Interaction[] memory intraInteractions)
        internal
        pure
        returns (
            address[] memory noTokens,
            uint256[] memory noPrices,
            ICowSettlement.Trade[] memory noTrades,
            ICowSettlement.Interaction[][3] memory interactions
        )
    {
        noTokens = new address[](0);
        noPrices = new uint256[](0);
        noTrades = new ICowSettlement.Trade[](0);
        ICowSettlement.Interaction[] memory noInteractions = new ICowSettlement.Interaction[](0);
        interactions = [noInteractions, intraInteractions, noInteractions];
    }
}
