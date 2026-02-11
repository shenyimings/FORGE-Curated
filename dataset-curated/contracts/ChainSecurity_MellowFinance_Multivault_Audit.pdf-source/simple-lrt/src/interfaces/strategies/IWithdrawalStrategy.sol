// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IWithdrawalStrategy {
    struct WithdrawalData {
        uint256 subvaultIndex;
        uint256 claimable;
        uint256 pending;
        uint256 staked;
    }

    function calculateWithdrawalAmounts(address vault, uint256 amount)
        external
        view
        returns (WithdrawalData[] memory subvaultsData);
}
