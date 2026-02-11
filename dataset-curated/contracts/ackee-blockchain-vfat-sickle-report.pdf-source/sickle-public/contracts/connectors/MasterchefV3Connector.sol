// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC721Enumerable } from
    "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";

import { Farm, NftPosition } from "contracts/interfaces/INftFarmConnector.sol";
import { SwapParams } from "contracts/interfaces/INftLiquidityConnector.sol";
import { INonfungiblePositionManager } from
    "contracts/interfaces/external/uniswap/INonfungiblePositionManager.sol";
import { IMasterchefV3 } from "contracts/interfaces/external/IMasterchefV3.sol";
import { UniswapV3Connector } from "contracts/connectors/UniswapV3Connector.sol";

contract MasterchefV3Connector is UniswapV3Connector {
    error Unsupported();

    function depositNewNft(
        Farm calldata farm,
        INonfungiblePositionManager nft,
        uint256 tokenIndex,
        bytes calldata // extraData
    ) external payable override {
        uint256 tokenId = IERC721Enumerable(nft).tokenOfOwnerByIndex(
            address(this), tokenIndex
        );

        IERC721Enumerable(nft).safeTransferFrom(
            address(this), farm.stakingContract, tokenId
        );
    }

    function depositExistingNft(
        NftPosition calldata position,
        bytes calldata // extraData
    ) external payable override {
        IERC721Enumerable(position.nft).safeTransferFrom(
            address(this), position.farm.stakingContract, position.tokenId
        );
    }

    function withdrawNft(
        NftPosition calldata position,
        bytes calldata // extraData
    ) external payable override {
        IMasterchefV3(position.farm.stakingContract).withdraw(
            position.tokenId, address(this)
        );
    }

    function claim(
        NftPosition calldata position,
        address[] memory, // rewardTokens
        uint128 amount0Max,
        uint128 amount1Max,
        bytes calldata // extraData
    ) external payable override {
        IMasterchefV3(position.farm.stakingContract).harvest(
            position.tokenId, address(this)
        );
        if (amount0Max > 0 || amount1Max > 0) {
            INonfungiblePositionManager.CollectParams memory params =
            INonfungiblePositionManager.CollectParams({
                tokenId: position.tokenId,
                recipient: address(this),
                amount0Max: amount0Max,
                amount1Max: amount1Max
            });
            INonfungiblePositionManager(position.farm.stakingContract).collect(
                params
            );
        }
    }

    function swapExactTokensForTokens(
        SwapParams memory
    ) external payable override {
        revert Unsupported();
    }
}
