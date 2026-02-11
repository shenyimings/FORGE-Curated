// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

interface IRewardDistributor {
    function comptroller() external view returns (address);

    function rewardMarketState(
        address rewardToken,
        address cToken
    )
        external
        view
        returns (
            uint256 supplySpeed,
            uint224 supplyIndex,
            uint32 supplyBlock,
            uint256 borrowSpeed,
            uint224 borrowIndex,
            uint32 borrowBlock
        );

    function rewardAccountState(
        address rewardToken,
        address account
    ) external view returns (uint256 rewardAccrued);

    function rewardTokens(uint256 index) external view returns (address);

    function rewardTokenExists(address rewardToken)
        external
        view
        returns (bool);

    function getBlockNumber() external view returns (uint32);
}
