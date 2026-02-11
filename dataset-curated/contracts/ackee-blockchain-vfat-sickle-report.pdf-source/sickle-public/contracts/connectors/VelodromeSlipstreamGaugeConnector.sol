// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IFarmConnector, Farm } from "contracts/interfaces/IFarmConnector.sol";
import { ICLGauge } from "contracts/interfaces/external/aerodrome/ICLGauge.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Enumerable } from
    "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";

// Either enter the existing token ID in case of increase/compound,
// or the balance index in case of deposit
struct VelodromeSlipstreamGaugeDepositExtraData {
    uint256 tokenId;
    // User's existing NFT balance in the Sickle, typically 0
    uint256 tokenBalance;
}

struct VelodromeSlipstreamGaugeClaimExtraData {
    uint256 tokenId;
}

struct VelodromeSlipstreamGaugeWithdrawExtraData {
    uint256 tokenId;
}

contract VelodromeSlipstreamGaugeConnector is IFarmConnector {
    function deposit(
        Farm calldata farm,
        address token,
        bytes memory extraData
    ) external payable override {
        VelodromeSlipstreamGaugeDepositExtraData memory data =
            abi.decode(extraData, (VelodromeSlipstreamGaugeDepositExtraData));
        uint256 tokenId = IERC721Enumerable(token).tokenOfOwnerByIndex(
            address(this), data.tokenBalance
        );

        IERC721(token).approve(farm.stakingContract, tokenId);
        ICLGauge(farm.stakingContract).deposit(tokenId);
    }

    function withdraw(
        Farm calldata farm,
        uint256, // amount
        bytes memory extraData
    ) external override {
        VelodromeSlipstreamGaugeWithdrawExtraData memory data =
            abi.decode(extraData, (VelodromeSlipstreamGaugeWithdrawExtraData));
        ICLGauge(farm.stakingContract).withdraw(data.tokenId);
    }

    function claim(
        Farm calldata farm,
        bytes memory extraData
    ) external override {
        VelodromeSlipstreamGaugeClaimExtraData memory data =
            abi.decode(extraData, (VelodromeSlipstreamGaugeClaimExtraData));
        ICLGauge(farm.stakingContract).getReward(data.tokenId);
    }
}
