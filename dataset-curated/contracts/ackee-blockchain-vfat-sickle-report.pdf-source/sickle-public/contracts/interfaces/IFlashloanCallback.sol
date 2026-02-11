// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IFlashloanCallback {
    /// Flashloan callbacks ///

    /// @notice Callback function for flashloan_withdraw()
    /// Repays the loaned amount, withdraws collateral and repays the flashloan
    function flashloanWithdrawCallback(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        bytes calldata extraData
    ) external;

    /// @notice Callback function for flashloan_deposit()
    /// Optionally swaps the flashloan for the collateral asset,
    /// supplies the loaned amount,
    /// borrows from the debt market (plus fee) to repay the flashloan
    function flashloanDepositCallback(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        bytes calldata extraData
    ) external;
}
