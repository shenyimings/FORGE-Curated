// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILeverageManager} from "./ILeverageManager.sol";

interface ILeverageToken is IERC20 {
    /// @notice Event emitted when the leverage token is initialized
    /// @param name The name of the LeverageToken
    /// @param symbol The symbol of the LeverageToken
    event LeverageTokenInitialized(string name, string symbol);

    /// @notice Converts an amount of LeverageToken shares to an amount of equity in collateral asset, based on the
    /// price oracle used by the underlying lending adapter and state of the LeverageToken.
    /// @notice Equity in collateral asset is equal to the difference between collateral and debt denominated
    /// in the collateral asset.
    /// @param shares The number of shares to convert to equity in collateral asset
    /// @return assets Amount of equity in collateral asset that correspond to the shares
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /// @notice Converts an amount of equity in collateral asset to an amount of LeverageToken shares, based on the
    /// price oracle used by the underlying lending adapter and state of the LeverageToken.
    /// @notice Equity in collateral asset is equal to the difference between collateral and debt denominated
    /// in the collateral asset.
    /// @param assets The amount of equity in collateral asset to convert to shares
    /// @return shares The number of shares that correspond to the equity in collateral asset
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /// @notice Mints new tokens to the specified address
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    /// @dev Only the owner can call this function. Owner should be the LeverageManager contract
    function mint(address to, uint256 amount) external;

    /// @notice Burns tokens from the specified address
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    /// @dev Only the owner can call this function. Owner should be the LeverageManager contract
    function burn(address from, uint256 amount) external;
}
