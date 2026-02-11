// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    INftFarmConnector,
    Farm,
    NftPosition
} from "contracts/interfaces/INftFarmConnector.sol";
import { ICLGauge } from "contracts/interfaces/external/aerodrome/ICLGauge.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Enumerable } from
    "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import { INonfungiblePositionManager } from
    "contracts/interfaces/external/uniswap/INonfungiblePositionManager.sol";

contract SlipstreamGaugeConnectorNew is INftFarmConnector {
    function depositNewNft(
        Farm calldata farm,
        INonfungiblePositionManager nft,
        uint256, // uses tokenOfOWnerByIndex to make the deposit
        bytes calldata // extraData
    ) external payable {
        uint256 balanceOf = IERC721(address(nft)).balanceOf(address(this));
        uint256 tokenId = IERC721Enumerable(address(nft)).tokenOfOwnerByIndex(
            address(this), balanceOf - 1
        );

        IERC721(address(nft)).approve(farm.stakingContract, tokenId);
        ICLGauge(farm.stakingContract).deposit(tokenId);
    }

    function depositExistingNft(
        NftPosition calldata position,
        bytes calldata // extraData
    ) external payable {
        IERC721(address(position.nft)).approve(
            position.farm.stakingContract, position.tokenId
        );
        ICLGauge(position.farm.stakingContract).deposit(position.tokenId);
    }

    function withdrawNft(
        NftPosition calldata position,
        bytes calldata // extraData
    ) external payable {
        ICLGauge(position.farm.stakingContract).withdraw(position.tokenId);
    }

    function claim(
        NftPosition calldata position,
        address[] memory, // rewardTokens
        uint128, // maxAmount0,
        uint128, // maxAmount1,
        bytes calldata // extraData
    ) external payable {
        ICLGauge(position.farm.stakingContract).getReward(position.tokenId);
    }
}
