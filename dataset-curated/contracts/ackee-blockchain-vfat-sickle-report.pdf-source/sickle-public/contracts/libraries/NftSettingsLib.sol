// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { INonfungiblePositionManager } from
    "contracts/interfaces/external/uniswap/INonfungiblePositionManager.sol";

import {
    INftSettingsRegistry,
    NftSettings,
    NftKey
} from "contracts/interfaces/INftSettingsRegistry.sol";
import { Sickle } from "contracts/Sickle.sol";

import { INftSettingsLib } from
    "contracts/interfaces/libraries/INftSettingsLib.sol";

contract NftSettingsLib is INftSettingsLib {
    function resetNftSettings(
        INftSettingsRegistry nftSettingsRegistry,
        INonfungiblePositionManager nftManager,
        uint256 tokenId
    ) external {
        NftKey memory key =
            NftKey(Sickle(payable(address(this))), nftManager, tokenId);
        NftSettings memory settings = nftSettingsRegistry.getNftSettings(key);

        uint256 newTokenId = nftManager.tokenOfOwnerByIndex(
            address(this), nftManager.balanceOf(address(this)) - 1
        );

        if (newTokenId == key.tokenId) {
            revert TokenIdUnchanged();
        }

        NftKey memory newKey = NftKey(key.sickle, key.nftManager, newTokenId);

        nftSettingsRegistry.resetNftSettings(key, newKey, settings);
    }

    function setNftSettings(
        INftSettingsRegistry nftSettingsRegistry,
        INonfungiblePositionManager nftManager,
        uint256 tokenId,
        NftSettings calldata settings
    ) external {
        NftKey memory key =
            NftKey(Sickle(payable(address(this))), nftManager, tokenId);
        nftSettingsRegistry.setNftSettings(key, settings);
    }
}
