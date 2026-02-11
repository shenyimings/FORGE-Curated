// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface ISmartTrendStrategy {
    function getMakerPayoff(uint256[2] memory anchorPrices, uint256 settlePrice, uint256 maxPayoff) external pure returns (uint256);
    function getMinterPayoff(uint256[2] memory anchorPrices, uint256 settlePrice, uint256 maxPayoff) external pure returns (uint256);
}
