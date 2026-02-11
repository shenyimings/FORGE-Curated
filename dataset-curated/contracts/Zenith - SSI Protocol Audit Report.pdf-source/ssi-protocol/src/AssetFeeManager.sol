// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;
import "./Interface.sol";
import {AssetController} from "./AssetController.sol";
import {Utils} from './Utils.sol';

import "forge-std/console.sol";

contract AssetFeeManager is AssetController, IAssetFeeManager {
    Request[] burnFeeRequests;

    event AddBurnFeeRequest(uint nonce);
    event RejectBurnFeeRequest(uint nonce);
    event ConfirmBurnFeeRequest(uint nonce);

    constructor(address owner, address factoryAddress_)
        AssetController(owner, factoryAddress_) {

    }

    function setFee(uint256 assetID, uint256 fee) external onlyOwner {
        IAssetFactory factory = IAssetFactory(factoryAddress);
        IAssetToken assetToken = IAssetToken(factory.assetTokens(assetID));
        require(assetToken.feeCollected(), "has fee not collected");
        require(assetToken.hasRole(assetToken.FEEMANAGER_ROLE(), address(this)), "not a fee manager");
        assetToken.setFee(fee);
    }

    function collectFeeTokenset(uint256 assetID) external onlyOwner {
        IAssetFactory factory = IAssetFactory(factoryAddress);
        IAssetToken assetToken = IAssetToken(factory.assetTokens(assetID));
        require(assetToken.hasRole(assetToken.FEEMANAGER_ROLE(), address(this)), "not a fee manager");
        require(assetToken.rebalancing() == false, "is rebalancing");
        require(assetToken.issuing() == false, "is issuing");
        assetToken.collectFeeTokenset();
    }

    function getBurnFeeRequestLength() external view returns (uint256) {
        return burnFeeRequests.length;
    }

    function getBurnFeeRequest(uint256 nonce) external view returns (Request memory) {
        return burnFeeRequests[nonce];
    }

    function addBurnFeeRequest(uint256 assetID, OrderInfo memory orderInfo) external onlyOwner returns (uint256) {
        IAssetFactory factory = IAssetFactory(factoryAddress);
        address assetTokenAddress = factory.assetTokens(assetID);
        IAssetToken assetToken = IAssetToken(assetTokenAddress);
        address swapAddress = factory.swap();
        ISwap swap = ISwap(swapAddress);
        require(assetToken.hasRole(assetToken.FEEMANAGER_ROLE(), address(this)), "not a fee manager");
        require(assetToken.burningFee() == false, "is burning fee");
        require(swap.checkOrderInfo(orderInfo) == 0, "order not valid");
        Token[] memory sellTokenset = Utils.muldivTokenset(orderInfo.order.inTokenset, orderInfo.order.inAmount, 10**8);
        require(Utils.containTokenset(assetToken.getFeeTokenset(), sellTokenset), "not enough fee to sell");
        for (uint i = 0; i < orderInfo.order.outTokenset.length; i++) {
            require(Utils.stringToAddress(orderInfo.order.outAddressList[i]) == factory.vault(), "fee receiver not match");
            require(bytes32(bytes(orderInfo.order.outTokenset[i].chain)) == bytes32(bytes(factory.chain())), "outTokenset chain not match");
        }
        swap.addSwapRequest(orderInfo, false, true);
        burnFeeRequests.push(Request({
            nonce: burnFeeRequests.length,
            requester: msg.sender,
            assetTokenAddress: assetTokenAddress,
            amount: 0,
            swapAddress: swapAddress,
            orderHash: orderInfo.orderHash,
            status: RequestStatus.PENDING,
            requestTimestamp: block.timestamp,
            issueFee: 0
        }));
        assetToken.lockBurnFee();
        emit AddBurnFeeRequest(burnFeeRequests.length - 1);
        return burnFeeRequests.length - 1;
    }

    function rejectBurnFeeRequest(uint nonce) external onlyOwner {
        require(nonce < burnFeeRequests.length);
        Request memory burnFeeRequest = burnFeeRequests[nonce];
        require(burnFeeRequest.status == RequestStatus.PENDING);
        ISwap swap = ISwap(burnFeeRequest.swapAddress);
        SwapRequest memory swapRequest = swap.getSwapRequest(burnFeeRequest.orderHash);
        require(swapRequest.status == SwapRequestStatus.REJECTED || swapRequest.status == SwapRequestStatus.CANCEL);
        IAssetToken assetToken = IAssetToken(burnFeeRequest.assetTokenAddress);
        assetToken.unlockBurnFee();
        burnFeeRequests[nonce].status = RequestStatus.REJECTED;
        emit RejectBurnFeeRequest(nonce);
    }

    function confirmBurnFeeRequest(uint nonce, OrderInfo memory orderInfo, bytes[] memory inTxHashs) external onlyOwner {
        require(nonce < burnFeeRequests.length);
        Request memory burnFeeRequest = burnFeeRequests[nonce];
        checkRequestOrderInfo(burnFeeRequest, orderInfo);
        require(burnFeeRequest.status == RequestStatus.PENDING);
        ISwap swap = ISwap(burnFeeRequest.swapAddress);
        SwapRequest memory swapRequest = swap.getSwapRequest(burnFeeRequest.orderHash);
        require(swapRequest.status == SwapRequestStatus.MAKER_CONFIRMED);
        swap.confirmSwapRequest(orderInfo, inTxHashs);
        IAssetToken assetToken = IAssetToken(burnFeeRequest.assetTokenAddress);
        Order memory order = orderInfo.order;
        Token[] memory sellTokenset = Utils.muldivTokenset(order.inTokenset, order.inAmount, 10**8);
        assetToken.burnFeeTokenset(sellTokenset);
        burnFeeRequests[nonce].status = RequestStatus.CONFIRMED;
        assetToken.unlockBurnFee();
        emit ConfirmBurnFeeRequest(nonce);
    }
}