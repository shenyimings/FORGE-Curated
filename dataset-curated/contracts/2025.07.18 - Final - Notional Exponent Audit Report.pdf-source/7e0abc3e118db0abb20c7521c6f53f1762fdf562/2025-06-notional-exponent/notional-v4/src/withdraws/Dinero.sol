// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {AbstractWithdrawRequestManager} from "./AbstractWithdrawRequestManager.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {WETH} from "../utils/Constants.sol";
import "../interfaces/IDinero.sol";

contract DineroWithdrawRequestManager is AbstractWithdrawRequestManager, ERC1155Holder {
    uint16 internal s_batchNonce;
    uint256 internal constant MAX_BATCH_ID = type(uint120).max;

    constructor(address pxETHorApxETH) AbstractWithdrawRequestManager(
        address(WETH), address(pxETHorApxETH), address(WETH)
    ) { }

    function _initiateWithdrawImpl(
        address /* account */,
        uint256 amountToWithdraw,
        bytes calldata /* data */
    ) override internal returns (uint256 requestId) {
        if (YIELD_TOKEN == address(apxETH)) {
            // First redeem the apxETH to pxETH before we initiate the redemption
            amountToWithdraw = apxETH.redeem(amountToWithdraw, address(this), address(this));
        }

        uint256 initialBatchId = PirexETH.batchId();
        pxETH.approve(address(PirexETH), amountToWithdraw);
        // TODO: what do we put for should trigger validator exit?
        PirexETH.initiateRedemption(amountToWithdraw, address(this), false);
        uint256 finalBatchId = PirexETH.batchId();
        uint256 nonce = ++s_batchNonce;

        // May require multiple batches to complete the redemption
        require(initialBatchId < MAX_BATCH_ID);
        require(finalBatchId < MAX_BATCH_ID);
        // Initial and final batch ids may overlap between requests so the nonce is used to ensure uniqueness
        return nonce << 240 | initialBatchId << 120 | finalBatchId;
    }

    function _stakeTokens(uint256 amount, bytes memory /* stakeData */) internal override {
        WETH.withdraw(amount);
        PirexETH.deposit{value: amount}(address(this), YIELD_TOKEN == address(apxETH));
    }

    function _decodeBatchIds(uint256 requestId) internal pure returns (uint256 initialBatchId, uint256 finalBatchId) {
        initialBatchId = requestId >> 120 & MAX_BATCH_ID;
        finalBatchId = requestId & MAX_BATCH_ID;
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        finalized = canFinalizeWithdrawRequest(requestId);

        if (finalized) {
            (uint256 initialBatchId, uint256 finalBatchId) = _decodeBatchIds(requestId);

            for (uint256 i = initialBatchId; i <= finalBatchId; i++) {
                uint256 assets = upxETH.balanceOf(address(this), i);
                if (assets == 0) continue;
                PirexETH.redeemWithUpxEth(i, assets, address(this));
                tokensClaimed += assets;
            }
        }

        WETH.deposit{value: tokensClaimed}();
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view returns (bool) {
        (uint256 initialBatchId, uint256 finalBatchId) = _decodeBatchIds(requestId);
        uint256 totalAssets;

        for (uint256 i = initialBatchId; i <= finalBatchId; i++) {
            IPirexETH.ValidatorStatus status = PirexETH.status(PirexETH.batchIdToValidator(i));

            if (status != IPirexETH.ValidatorStatus.Dissolved && status != IPirexETH.ValidatorStatus.Slashed) {
                // Can only finalize if all validators are dissolved or slashed
                return false;
            }

            totalAssets += upxETH.balanceOf(address(this), i);
        }

        // Can only finalize if the total assets are greater than the outstanding redemptions
        return PirexETH.outstandingRedemptions() > totalAssets;
    }
}