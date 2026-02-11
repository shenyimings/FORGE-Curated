// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IFarmConnector, Farm } from "contracts/interfaces/IFarmConnector.sol";
import { ICLGauge } from "contracts/interfaces/external/aerodrome/ICLGauge.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Enumerable } from
    "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";

// Either enter the existing token ID in case of increase/compound,
// or the balance index in case of deposit
struct AerodromeSlipstreamGaugeDepositExtraData {
    uint256 tokenId;
    // User's existing NFT balance in the Sickle, typically 0
    uint256 tokenBalance;
}

struct AerodromeSlipstreamGaugeClaimExtraData {
    uint256 tokenId;
}

struct AerodromeSlipstreamGaugeWithdrawExtraData {
    uint256 tokenId;
}

contract AerodromeSlipstreamGaugeConnector is IFarmConnector {
    function deposit(
        Farm calldata farm,
        address token,
        bytes memory extraData
    ) external payable override {
        AerodromeSlipstreamGaugeDepositExtraData memory data =
            abi.decode(extraData, (AerodromeSlipstreamGaugeDepositExtraData));
        if (data.tokenId == 0) {
            data.tokenId = IERC721Enumerable(token).tokenOfOwnerByIndex(
                address(this), data.tokenBalance
            );
        }

        IERC721(token).approve(farm.stakingContract, data.tokenId);
        ICLGauge(farm.stakingContract).deposit(data.tokenId);
    }

    function withdraw(
        Farm calldata farm,
        uint256, // amount
        bytes memory extraData
    ) external override {
        AerodromeSlipstreamGaugeWithdrawExtraData memory data =
            abi.decode(extraData, (AerodromeSlipstreamGaugeWithdrawExtraData));
        ICLGauge(farm.stakingContract).withdraw(data.tokenId);
    }

    function claim(
        Farm calldata farm,
        bytes memory extraData
    ) external override {
        AerodromeSlipstreamGaugeClaimExtraData memory data =
            abi.decode(extraData, (AerodromeSlipstreamGaugeClaimExtraData));
        ICLGauge(farm.stakingContract).getReward(data.tokenId);
    }
}
