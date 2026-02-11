// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { INonfungiblePositionManager } from
    "contracts/interfaces/external/uniswap/INonfungiblePositionManager.sol";

import { Sickle } from "contracts/Sickle.sol";

abstract contract NftFarmStrategyEvents {
    event SickleDepositedNft(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex,
        INonfungiblePositionManager nft,
        uint256 tokenId
    );

    event SickleIncreasedNft(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex,
        INonfungiblePositionManager nft,
        uint256 tokenId
    );

    event SickleHarvestedNft(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex,
        INonfungiblePositionManager nft,
        uint256 tokenId
    );

    event SickleCompoundedNft(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex,
        INonfungiblePositionManager nft,
        uint256 tokenId
    );

    event SickleWithdrewNft(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex,
        INonfungiblePositionManager nft,
        uint256 tokenId
    );

    event SickleDecreasedNft(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex,
        INonfungiblePositionManager nft,
        uint256 tokenId
    );

    event SickleExitedNft(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex,
        INonfungiblePositionManager nft,
        uint256 tokenId
    );

    event SickleRebalancedNft(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex,
        INonfungiblePositionManager nft,
        uint256 tokenId
    );
}
