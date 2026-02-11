// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC7496} from "../interfaces/IERC7496.sol";

import {INeuV2} from "./INeuV2.sol";

interface INeuV3 is INeuV2, IERC7496 {
    event InitializedNeuV3(
        address payable indexed royaltyReceiver,
        address indexed metadataAddress,
        address payable indexed lockV2Contract
    );
    event RoyaltyReceiverUpdated(address indexed royaltyReceiver);
    event EntitlementTimestampSet(uint256 indexed tokenId, uint256 timestamp);

    error Deprecated();

    function initializeV3(
        address payable royaltyReceiver,
        address metadataAddress,
        address payable lockV2Address,
        string calldata traitMetadataUri
    ) external;
    function setRoyaltyReceiver(address royaltyReceiver) external;
    function entitlementAfterTimestamps(uint256 tokenId) external view returns (uint256);
}

interface INeuTokenV3 is INeuV3, IERC721Enumerable {}