// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IPolygonStakeManager {
    function withdrawalDelay() external view returns (uint256);

    function epoch() external view returns (uint256);
}
