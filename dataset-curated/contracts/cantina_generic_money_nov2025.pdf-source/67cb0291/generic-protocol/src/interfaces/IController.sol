// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IController
 * @notice Interface for the Controller contract that handles conversion logic and share token operations
 * @dev This interface defines the core functionality for asset-to-share conversion calculations
 *      and share token minting/burning. The Controller is called by vaults to perform
 *      conversion logic while the vaults themselves handle asset transfers
 */
interface IController {
    /**
     * @notice Returns the address of the Vault for the given asset
     * @param asset The address of the asset
     * @return The address of the associated Vault
     */
    function vaultFor(address asset) external view returns (address);

    /**
     * @notice Returns the address of the share token contract
     * @return The address of the share token
     */
    function share() external view returns (address);

    /**
     * @notice Calculates shares to mint and mints share tokens based on deposited assets
     * @dev Called by vaults after they receive asset transfers. Handles conversion logic and share minting
     * @param assets The amount of assets that were deposited into the vault
     * @param receiver The address that will receive the minted shares
     * @return shares The amount of shares minted to the receiver
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /**
     * @notice Calculates required assets and mints specified shares to receiver
     * @dev Called by vaults to determine asset requirements and mint share tokens
     * @param shares The amount of shares to mint
     * @param receiver The address that will receive the minted shares
     * @return assets The amount of assets required from the vault for the minted shares
     */
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /**
     * @notice Calculates shares to burn and burns them for asset withdrawal
     * @dev Called by vaults before they transfer assets. Handles conversion logic and share burning
     * @param assets The amount of assets to be withdrawn by the vault
     * @param spender The address that is burning the shares
     * @param owner The address that owns the shares being burned
     * @return shares The amount of shares burned from the owner
     */
    function withdraw(uint256 assets, address spender, address owner) external returns (uint256 shares);

    /**
     * @notice Burns specified shares and calculates equivalent asset amount
     * @dev Called by vaults to burn share tokens and determine asset transfer amounts
     * @param shares The amount of shares to burn
     * @param spender The address that is burning the shares
     * @param owner The address that owns the shares being burned
     * @return assets The amount of assets the vault should transfer to the receiver
     */
    function redeem(uint256 shares, address spender, address owner) external returns (uint256 assets);

    /**
     * @notice Calculates the amount of shares that would be minted for a given asset amount
     * @param assets The amount of assets to calculate shares for
     * @return shares The amount of shares that would be minted
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Calculates the amount of assets required to mint a specified amount of shares
     * @param shares The amount of shares to calculate asset requirements for
     * @return assets The amount of assets required to mint the specified shares
     */
    function previewMint(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Calculates the amount of shares that would be burned for a given asset withdrawal
     * @param assets The amount of assets to calculate share burn for
     * @return shares The amount of shares that would be burned
     */
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Calculates the amount of assets equivalent to burning specified shares
     * @param shares The amount of shares to calculate asset equivalent for
     * @return assets The amount of assets equivalent to the specified shares
     */
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Returns the maximum amount of assets that can be processed for share minting
     * @param receiver The address that would receive the minted shares
     * @return The maximum amount of assets that can be converted to shares
     */
    function maxDeposit(address receiver) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of shares that can be minted to the receiver
     * @param receiver The address that would receive the minted shares
     * @return The maximum amount of shares that can be minted
     */
    function maxMint(address receiver) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of assets that can be processed for share burning
     * @param owner The address that owns the shares
     * @param availableAssets The amount of assets currently available in the vault
     * @return The maximum amount of assets that can be withdrawn through share burning
     */
    function maxWithdraw(address owner, uint256 availableAssets) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of shares that can be burned by the owner
     * @param owner The address that owns the shares
     * @param availableAssets The amount of assets currently available in the vault
     * @return The maximum amount of shares that can be redeemed
     */
    function maxRedeem(address owner, uint256 availableAssets) external view returns (uint256);
}
