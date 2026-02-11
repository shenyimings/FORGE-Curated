// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { PredepositCoordinator } from "../../src/coordinator/PredepositCoordinator.sol";

import { BridgeCoordinatorHarness } from "./BridgeCoordinatorHarness.sol";

contract BridgeCoordinatorPredepositHarness is BridgeCoordinatorHarness, PredepositCoordinator {
    function _storage() private pure returns (PredepositCoordinatorStorage storage $) {
        assembly {
            $.slot := 0xc21018d819991b3ffe7c98205610e4fd64c7a07a5010749045af9b9d7860c300
        }
    }

    function workaround_setPredepositState(
        bytes32 chainNickname,
        PredepositCoordinator.PredepositState state
    )
        external
    {
        PredepositCoordinatorStorage storage $ = _storage();
        $.chain[chainNickname].state = state;
    }

    function workaround_setPredepositChainId(bytes32 chainNickname, uint256 chainId) external {
        PredepositCoordinatorStorage storage $ = _storage();
        $.chain[chainNickname].chainId = chainId;
    }

    function workaround_setPredeposit(
        bytes32 chainNickname,
        address sender,
        bytes32 recipient,
        uint256 amount
    )
        external
    {
        PredepositCoordinatorStorage storage $ = _storage();
        $.chain[chainNickname].predeposits[sender][recipient] = amount;
    }

    function workaround_setTotalPredeposits(bytes32 chainNickname, uint256 totalAmount) external {
        PredepositCoordinatorStorage storage $ = _storage();
        $.chain[chainNickname].totalPredeposits = totalAmount;
    }
}
