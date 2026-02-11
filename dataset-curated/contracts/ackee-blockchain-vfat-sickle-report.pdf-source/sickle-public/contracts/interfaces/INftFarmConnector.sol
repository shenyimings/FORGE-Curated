// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { INonfungiblePositionManager } from
    "contracts/interfaces/external/uniswap/INonfungiblePositionManager.sol";
import { Farm } from "contracts/structs/FarmStrategyStructs.sol";
import { NftPosition } from "contracts/structs/NftFarmStrategyStructs.sol";

interface INftFarmConnector {
    function depositNewNft(
        Farm calldata farm,
        INonfungiblePositionManager nft,
        uint256 tokenIndex, // uses tokenOfOWnerByIndex to make the deposit
        bytes calldata extraData
    ) external payable;

    function depositExistingNft(
        NftPosition calldata position,
        bytes calldata extraData
    ) external payable;

    function withdrawNft(
        NftPosition calldata position,
        bytes calldata extraData
    ) external payable;
    // Payable in case an NFT is withdrawn to be increased with ETH

    function claim(
        NftPosition calldata position,
        address[] memory rewardTokens,
        uint128 maxAmount0, // For collecting
        uint128 maxAmount1,
        bytes calldata extraData
    ) external payable;
}
