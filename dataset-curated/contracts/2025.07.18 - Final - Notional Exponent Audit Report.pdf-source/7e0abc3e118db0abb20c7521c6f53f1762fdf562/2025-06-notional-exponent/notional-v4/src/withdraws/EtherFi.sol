// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {AbstractWithdrawRequestManager} from "./AbstractWithdrawRequestManager.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {WETH} from "../utils/Constants.sol";
import "../interfaces/IEtherFi.sol";

contract EtherFiWithdrawRequestManager is AbstractWithdrawRequestManager, ERC721Holder {

    constructor() AbstractWithdrawRequestManager(address(WETH), address(weETH), address(WETH)) { }

    function _initiateWithdrawImpl(
        address /* account */,
        uint256 weETHToUnwrap,
        bytes calldata /* data */
    ) override internal returns (uint256 requestId) {
        uint256 balanceBefore = eETH.balanceOf(address(this));
        weETH.unwrap(weETHToUnwrap);
        uint256 balanceAfter = eETH.balanceOf(address(this));
        uint256 eETHReceived = balanceAfter - balanceBefore;

        eETH.approve(address(LiquidityPool), eETHReceived);
        return LiquidityPool.requestWithdraw(address(this), eETHReceived);
    }

    function _stakeTokens(uint256 amount, bytes memory /* stakeData */) internal override {
        WETH.withdraw(amount);
        uint256 eEthBalBefore = eETH.balanceOf(address(this));
        LiquidityPool.deposit{value: amount}();
        uint256 eETHMinted = eETH.balanceOf(address(this)) - eEthBalBefore;
        eETH.approve(address(weETH), eETHMinted);
        weETH.wrap(eETHMinted);
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        finalized = canFinalizeWithdrawRequest(requestId);

        if (finalized) {
            uint256 balanceBefore = address(this).balance;
            WithdrawRequestNFT.claimWithdraw(requestId);
            tokensClaimed = address(this).balance - balanceBefore;
            WETH.deposit{value: tokensClaimed}();
        }
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view override returns (bool) {
        return (
            WithdrawRequestNFT.isFinalized(requestId) &&
            WithdrawRequestNFT.ownerOf(requestId) != address(0)
        );
    }
}

