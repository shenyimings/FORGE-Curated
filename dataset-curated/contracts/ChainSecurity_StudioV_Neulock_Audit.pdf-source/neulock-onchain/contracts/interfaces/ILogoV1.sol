// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

interface INeuLogoV1 {
    function makeLogo(string calldata tokenId, string calldata seriesName, uint16 foregroundColor, uint16 backgroundColor, uint16 accentColor) external view returns (string memory);
}