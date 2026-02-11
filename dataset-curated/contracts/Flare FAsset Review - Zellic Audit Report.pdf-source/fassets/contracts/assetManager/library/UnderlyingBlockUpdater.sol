// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AssetManagerState} from "./data/AssetManagerState.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {Globals} from "./Globals.sol";
import {TransactionAttestation} from "./TransactionAttestation.sol";
import {IConfirmedBlockHeightExists, IPayment} from
    "@flarenetwork/flare-periphery-contracts/flare/IFdcVerification.sol";


library UnderlyingBlockUpdater {
    using SafeCast for uint256;

    function updateCurrentBlock(IConfirmedBlockHeightExists.Proof calldata _proof)
        internal
    {
        TransactionAttestation.verifyConfirmedBlockHeightExists(_proof);
        updateCurrentBlock(_proof.data.requestBody.blockNumber, _proof.data.responseBody.blockTimestamp,
            _proof.data.responseBody.numberOfConfirmations);
    }

    function updateCurrentBlockForVerifiedPayment(IPayment.Proof calldata _proof)
        internal
    {
        // This is used in various payment methods, where the proof is already verified, so we don't verify again.
        // Payment proof doesn't include confirmation blocks, but at least 1 confirmation is required on every chain,
        // so we set _numberOfConfirmations to 1. The update happens only when block and timestamp increase,
        // so this cannot make the block number or timestamp approximation worse.
        updateCurrentBlock(_proof.data.responseBody.blockNumber, _proof.data.responseBody.blockTimestamp, 1);
    }

    function updateCurrentBlock(uint64 _blockNumber, uint64 _blockTimestamp, uint64 _numberOfConfirmations)
        internal
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        bool changed = false;
        uint64 finalizationBlockNumber = _blockNumber + _numberOfConfirmations;
        if (finalizationBlockNumber > state.currentUnderlyingBlock) {
            state.currentUnderlyingBlock = finalizationBlockNumber;
            changed = true;
        }
        uint256 finalizationBlockTimestamp = _blockTimestamp +
            _numberOfConfirmations * Globals.getSettings().averageBlockTimeMS / 1000;
        if (finalizationBlockTimestamp > state.currentUnderlyingBlockTimestamp) {
            state.currentUnderlyingBlockTimestamp = finalizationBlockTimestamp.toUint64();
            changed = true;
        }
        if (changed) {
            state.currentUnderlyingBlockUpdatedAt = block.timestamp.toUint64();
            emit IAssetManagerEvents.CurrentUnderlyingBlockUpdated(
                state.currentUnderlyingBlock, state.currentUnderlyingBlockTimestamp, block.timestamp);
        }
    }
}
