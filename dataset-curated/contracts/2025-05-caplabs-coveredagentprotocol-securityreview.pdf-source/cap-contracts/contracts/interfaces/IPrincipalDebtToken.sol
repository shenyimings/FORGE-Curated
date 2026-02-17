// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IPrincipalDebtToken {
    /// @custom:storage-location erc7201:cap.storage.PrincipalDebt
    struct PrincipalDebtTokenStorage {
        address asset;
        uint8 decimals;
    }

    /// @dev Operation not supported
    error OperationNotSupported();

    /// @notice Initialize the principal debt token
    /// @param _accessControl Access control address
    /// @param _asset Asset address
    function initialize(address _accessControl, address _asset) external;

    /// @notice Lender will mint debt tokens to match the amount borrowed by an agent. Interest and
    /// restaker interest is accrued to the agent.
    /// @param to Address to mint tokens to
    /// @param amount Amount of tokens to mint
    function mint(address to, uint256 amount) external;

    /// @notice Lender will burn debt tokens when the principal debt is repaid by an agent
    /// @param from Burn tokens from agent
    /// @param amount Amount to burn
    function burn(address from, uint256 amount) external;
}
