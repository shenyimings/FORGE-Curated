// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ITellerWithMultiAssetSupport {
    function authority() external view returns (address);
    function accountant() external view returns (address);
    function vault() external view returns (address);
    function updateAssetData(ERC20 asset, bool allowDeposits, bool allowWithdraws, uint16 sharePremium) external;
    function deposit(ERC20 depositAsset, uint256 depositAmount, uint256 minimumMint, address referralAddress)
        external
        returns (uint256 shares);
    function bulkDeposit(ERC20 depositAsset, uint256 depositAmount, uint256 minimumMint, address to)
        external
        returns (uint256 shares);
    function bulkWithdraw(ERC20 withdrawAsset, uint256 shareAmount, uint256 minimumAssets, address to)
        external
        returns (uint256 assetsOut);
}
