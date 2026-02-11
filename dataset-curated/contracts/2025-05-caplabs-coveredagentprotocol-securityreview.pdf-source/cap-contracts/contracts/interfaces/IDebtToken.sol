// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IDebtToken {
    /// @custom:storage-location erc7201:cap.storage.DebtToken
    struct DebtTokenStorage {
        address asset;
        address oracle;
        uint256 index;
        uint256 lastIndexUpdate;
        uint256 interestRate;
    }

    /// @notice Initialize the debt token
    /// @param _accessControl Access control address
    /// @param _asset Asset address
    /// @param _oracle Oracle address
    function initialize(address _accessControl, address _asset, address _oracle) external;

    /// @notice Lender will mint debt tokens to match the amount debt owed by an agent
    /// @param to Address to mint tokens to
    /// @param amount Amount of tokens to mint
    function mint(address to, uint256 amount) external;

    /// @notice Lender will burn debt tokens when the debt is repaid by an agent
    /// @param from Burn tokens from agent
    /// @param amount Amount to burn
    function burn(address from, uint256 amount) external;
}
