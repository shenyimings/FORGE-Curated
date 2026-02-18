// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {AbstractWithdrawRequestManager} from "./AbstractWithdrawRequestManager.sol";
import {WETH} from "../utils/Constants.sol";
import "../interfaces/IOrigin.sol";

contract OriginWithdrawRequestManager is AbstractWithdrawRequestManager {

    constructor() AbstractWithdrawRequestManager(address(WETH), address(oETH), address(WETH)) { }

    function _initiateWithdrawImpl(
        address /* account */,
        uint256 oETHToWithdraw,
        bytes calldata /* data */
    ) override internal returns (uint256 requestId) {
        ERC20(YIELD_TOKEN).approve(address(OriginVault), oETHToWithdraw);
        (requestId, ) = OriginVault.requestWithdrawal(oETHToWithdraw);
    }

    function _stakeTokens(uint256 amount, bytes memory stakeData) internal override {
        uint256 minAmountOut;
        if (stakeData.length > 0) (minAmountOut) = abi.decode(stakeData, (uint256));
        WETH.approve(address(OriginVault), amount);
        OriginVault.mint(address(WETH), amount, minAmountOut);
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        finalized = canFinalizeWithdrawRequest(requestId);

        if (finalized) {
            uint256 balanceBefore = WETH.balanceOf(address(this));
            OriginVault.claimWithdrawal(requestId);
            tokensClaimed = WETH.balanceOf(address(this)) - balanceBefore;
        }
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view returns (bool) {
        IOriginVault.WithdrawalRequest memory request = OriginVault.withdrawalRequests(requestId);
        IOriginVault.WithdrawalQueueMetadata memory queue = OriginVault.withdrawalQueueMetadata();
        uint256 withdrawalClaimDelay = OriginVault.withdrawalClaimDelay();

        bool claimDelayMet = request.timestamp + withdrawalClaimDelay <= block.timestamp;
        bool queueLiquidityAvailable = request.queued <= queue.claimable;
        bool notClaimed = request.claimed == false;

        return claimDelayMet && queueLiquidityAvailable && notClaimed;
    }
}