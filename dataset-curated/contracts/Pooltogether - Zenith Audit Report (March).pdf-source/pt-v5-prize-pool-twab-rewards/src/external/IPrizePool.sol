// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPrizePool {
    function getTotalContributedBetween(
        uint24 _startDrawIdInclusive,
        uint24 _endDrawIdInclusive
    ) external view returns (uint256);

    function getContributedBetween(
        address _vault,
        uint24 _startDrawIdInclusive,
        uint24 _endDrawIdInclusive
    ) external view returns (uint256);

    function drawPeriodSeconds() external view returns (uint48);
    function firstDrawOpensAt() external view returns (uint48);
}
