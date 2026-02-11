// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {INeuMetadataV1} from "./INeuMetadataV1.sol";

struct Series {
    bytes8 name;
    uint64 priceInGwei;
    uint32 firstToken;
    uint32 maxTokens;
    uint32 mintedTokens;
    uint32 burntTokens;
    uint16 fgColorRGB565;
    uint16 bgColorRGB565;
    uint16 accentColorRGB565;
}

struct TokenMetadata {
    uint64 originalPriceInGwei;
    uint64 sponsorPoints;
    uint40 mintedAt;
}

interface INeuMetadataV2 is INeuMetadataV1 {
    event InitializedMetadata(uint256 version, address defaultAdmin, address upgrader, address operator, address neuContract, address logoContract);
    event TokenMetadataUpdated(uint256 indexed tokenId, TokenMetadata metadata);
    event TokenMetadataDeleted(uint256 indexed tokenId);
    event MetadataURIUpdated(string uri);
    event TraitUpdated(bytes32 indexed traitName, uint256 tokenId, bytes32 traitValue);
    event SeriesAdded(uint16 indexed seriesIndex, bytes8 indexed name, uint64 priceInGwei, uint32 firstToken, uint32 maxTokens, uint16 fgColorRGB565, uint16 bgColorRGB565, uint16 accentColorRGB565, bool makeAvailable);
    event SeriesAvailabilityUpdated(uint16 indexed seriesIndex, bool available);
    event SeriesPriceUpdated(uint16 indexed seriesIndex, uint64 priceInGwei);
    event LogoUpdated(address logoContract);

    function isGovernanceToken(uint256 tokenId) external view returns (bool);
}