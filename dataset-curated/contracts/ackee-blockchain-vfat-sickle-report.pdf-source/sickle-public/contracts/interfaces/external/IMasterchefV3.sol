// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMasterchefV3 {
    function harvest(
        uint256 _tokenId,
        address _to
    ) external returns (uint256 reward);
    function withdraw(
        uint256 _tokenId,
        address _to
    ) external returns (uint256 reward);
    function pendingCake(uint256 _tokenId)
        external
        view
        returns (uint256 reward);
    function nonfungiblePositionManager() external view returns (address);
}
