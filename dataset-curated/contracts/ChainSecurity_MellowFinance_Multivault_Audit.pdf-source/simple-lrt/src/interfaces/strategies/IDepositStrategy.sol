// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IDepositStrategy {
    struct DepositData {
        uint256 subvaultIndex;
        uint256 deposit;
    }

    function calculateDepositAmounts(address vault, uint256 assets)
        external
        view
        returns (DepositData[] memory subvaultsData);
}
