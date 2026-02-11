// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { INonfungiblePositionManager } from
    "contracts/interfaces/external/uniswap/INonfungiblePositionManager.sol";

import {
    INftSettingsRegistry,
    NftSettings,
    NftKey
} from "contracts/interfaces/INftSettingsRegistry.sol";

interface INftSettingsLib {
    error TokenIdUnchanged();

    function resetNftSettings(
        INftSettingsRegistry nftSettingsRegistry,
        INonfungiblePositionManager nftManager,
        uint256 tokenId
    ) external;

    function setNftSettings(
        INftSettingsRegistry nftSettingsRegistry,
        INonfungiblePositionManager nftManager,
        uint256 tokenId,
        NftSettings calldata settings
    ) external;
}
