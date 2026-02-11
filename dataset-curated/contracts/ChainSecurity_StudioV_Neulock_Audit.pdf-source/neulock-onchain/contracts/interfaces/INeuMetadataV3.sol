// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Series, TokenMetadata, INeuMetadataV2} from "./INeuMetadataV2.sol";

interface INeuMetadataV3 is INeuMetadataV2 {
    event InitializedMetadataV3();

    function createTokenMetadataV3(uint16 seriesIndex, uint256 originalPrice) external returns (uint256 tokenId);
}