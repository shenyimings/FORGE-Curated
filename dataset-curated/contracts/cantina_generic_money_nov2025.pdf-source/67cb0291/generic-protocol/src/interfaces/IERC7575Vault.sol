// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IERC7575Vault
 * @notice Interface for ERC7575-compliant vault contracts
 * @dev This interface defines the core vault operations for managing individual collateral assets
 * within the multi-asset ecosystem.
 */
interface IERC7575Vault {
    /**
     * @notice Emitted when assets are deposited into the vault
     * @dev This event follows the ERC7575 standard for deposit operations
     * @param sender The address that initiated the deposit transaction
     * @param owner The address that will own the minted shares (same as receiver in this implementation)
     * @param assets The amount of underlying assets deposited
     * @param shares The amount of shares minted (calculated using dynamic pricing)
     */
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when assets are withdrawn from the vault
     * @dev This event follows the ERC7575 standard for withdrawal operations
     * @param sender The address that initiated the withdrawal transaction
     * @param receiver The address that receives the withdrawn assets
     * @param owner The address that owns the shares being redeemed
     * @param assets The amount of underlying assets withdrawn
     * @param shares The amount of shares burned (calculated using dynamic pricing)
     */
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /**
     * @notice Returns the address of the share token
     * @return The address of the share token contract
     */
    function share() external view returns (address);

    /**
     * @notice Returns the address of the underlying asset token
     * @dev Each vault manages a single underlying asset
     * @return The address of the underlying asset ERC20 contract
     */
    function asset() external view returns (address);

    /**
     * @notice Returns the total amount of underlying assets managed by the vault
     * @dev This includes assets held directly in the vault plus assets deployed to yield strategies
     * @return The total amount of underlying assets in the vault's management
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Converts an amount of assets to the equivalent amount of shares
     * @dev Returns the exchange rate between vault shares and underlying assets.
     * Always returns a 1:1 ratio because to calculate the proper value via dynamic pricing,
     * the contract would need to know if it's a deposit or withdraw operation.
     * @param assets The amount of underlying assets to convert
     * @return The equivalent amount of shares
     */
    function convertToShares(uint256 assets) external view returns (uint256);

    /**
     * @notice Converts an amount of shares to the equivalent amount of assets
     * @dev Returns the exchange rate between vault shares and underlying assets.
     * Always returns a 1:1 ratio because to calculate the proper value via dynamic pricing,
     * the contract would need to know if it's a deposit or withdraw operation.
     * @param shares The amount of shares to convert
     * @return The equivalent amount of underlying assets
     */
    function convertToAssets(uint256 shares) external view returns (uint256);

    /**
     * @notice Deposits assets into the vault and mints shares to the receiver
     * @param assets The amount of underlying assets to deposit
     * @param receiver The address that will receive the minted shares
     * @return shares The amount of shares minted (calculated using dynamic pricing)
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /**
     * @notice Mints a specific amount of shares by depositing the required assets
     * @param shares The exact amount of shares to mint
     * @param receiver The address that will receive the minted shares
     * @return assets The amount of underlying assets required and deposited
     */
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /**
     * @notice Withdraws a specific amount of assets by burning the required shares
     * @param assets The exact amount of underlying assets to withdraw
     * @param receiver The address that will receive the withdrawn assets
     * @param owner The address that owns the shares to be burned
     * @return shares The amount of shares burned (calculated using dynamic pricing)
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /**
     * @notice Burns shares and withdraws the equivalent amount of assets
     * @param shares The amount of shares to burn
     * @param receiver The address that will receive the withdrawn assets
     * @param owner The address that owns the shares to be burned
     * @return assets The amount of underlying assets withdrawn (calculated using dynamic pricing)
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /**
     * @notice Simulates the effects of a deposit without executing it
     * @dev Calculates how many shares would be minted for a given asset deposit
     * using current dynamic pricing from the Controller
     * @param assets The amount of underlying assets to simulate depositing
     * @return shares The amount of shares that would be minted
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Simulates the effects of a mint without executing it
     * @dev Calculates how many assets would be required to mint a given amount of shares
     * using current dynamic pricing from the Controller
     * @param shares The amount of shares to simulate minting
     * @return assets The amount of underlying assets that would be required
     */
    function previewMint(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Simulates the effects of a withdrawal without executing it
     * @dev Calculates how many shares would be burned for a given asset withdrawal
     * using current dynamic pricing from the Controller
     * @param assets The amount of underlying assets to simulate withdrawing
     * @return shares The amount of shares that would be burned
     */
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Simulates the effects of a redemption without executing it
     * @dev Calculates how many assets would be withdrawn for a given amount of shares
     * using current dynamic pricing from the Controller
     * @param shares The amount of shares to simulate redeeming
     * @return assets The amount of underlying assets that would be withdrawn
     */
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Returns the maximum amount of assets that can be deposited for a given receiver
     * @dev Takes into account vault capacity limits
     * @param receiver The address that would receive the minted shares
     * @return The maximum amount of underlying assets that can be deposited
     */
    function maxDeposit(address receiver) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of shares that can be minted for a given receiver
     * @dev Takes into account vault capacity limits
     * @param receiver The address that would receive the minted shares
     * @return The maximum amount of shares that can be minted
     */
    function maxMint(address receiver) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn by a given owner
     * @dev Takes into account owner's share balance and vault capacity limits
     * @param owner The address that owns the shares to be burned
     * @return The maximum amount of underlying assets that can be withdrawn
     */
    function maxWithdraw(address owner) external view returns (uint256);

    /**
     * @notice Returns the maximum amount of shares that can be redeemed by a given owner
     * @dev Takes into account owner's share balance and vault capacity limits
     * @param owner The address that owns the shares to be burned
     * @return The maximum amount of shares that can be redeemed
     */
    function maxRedeem(address owner) external view returns (uint256);
}
