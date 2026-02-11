// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

interface ITheGraphStaking {
    function delegationPools(address _indexer)
        external
        view
        returns (
            uint32 cooldownBlocks_,
            uint32 indexingRewardCut_,
            uint32 queryFeeCut_,
            uint256 updatedAtBlock_,
            uint256 poolTokens_,
            uint256 poolShares_
        );

    function delegationTaxPercentage() external view returns (uint32 taxPercentage_);

    function getDelegation(address _indexer, address _delegator)
        external
        view
        returns (uint256 shares_, uint256 tokensLocked_, uint256 tokensLockedUntil_);
}
