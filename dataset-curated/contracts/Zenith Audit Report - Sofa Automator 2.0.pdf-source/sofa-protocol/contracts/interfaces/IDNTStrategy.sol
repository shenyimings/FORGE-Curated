// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IDNTStrategy {
    function getMakerPayoff(uint256[2] memory anchorPrices, uint256[2] memory settlePrices, uint256 maxPayoff) external pure returns (uint256);
    function getMinterPayoff(uint256[2] memory anchorPrices, uint256[2] memory settlePrices, uint256 maxPayoff) external pure returns (uint256);
}
