// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IControlledVault
 * @notice Interface for vaults that can be managed by a controller contract
 * @dev This interface enables controller contracts to interact with and manage vault operations,
 * particularly for rebalancing and asset management purposes. Implementing contracts must
 * ensure proper access control to prevent unauthorized operations.
 */
interface IControlledVault {
    /**
     * @notice Emitted when assets are withdrawn from the vault by the controller
     * @dev This event is triggered when the controller initiates a withdrawal for
     * rebalancing operations or rewards swapping activities
     * @param asset The address of the asset withdrawn (can be a reward token)
     * @param assets The amount of assets withdrawn from the vault
     * @param receiver The address that received the withdrawn assets
     */
    event ControllerWithdraw(address indexed asset, uint256 assets, address indexed receiver);

    /**
     * @notice Emitted when assets are deposited into the vault by the controller
     * @dev This event is triggered when the controller deposits assets into the vault
     * for rebalancing operations or following rewards swapping activities
     * @param assets The amount of assets deposited into the vault
     */
    event ControllerDeposit(uint256 assets);

    /**
     * @notice Thrown when a caller other than the designated controller attempts to perform
     * a controller-only operation
     * @dev This error ensures that only the authorized controller can execute sensitive
     * vault management functions
     */
    error CallerNotController();

    /**
     * @notice Returns the address of the underlying asset managed by the vault
     * @dev This is typically an ERC20 token address that the vault holds and manages
     * @return The address of the underlying asset
     */
    function asset() external view returns (address);

    /**
     * @notice Returns the address of the controller contract that manages this vault
     * @dev The controller has special privileges to perform operations like rebalancing
     * @return The address of the controller contract
     */
    function controller() external view returns (address);

    /**
     * @notice Returns the total amount of normalized assets held by the vault
     * @dev Normalized assets are standardized to 18 decimals regardless of the underlying
     * asset's actual decimal places. The vault automatically scales asset amounts
     * up or down to maintain this 18-decimal standard for consistent cross-vault
     * calculations and comparisons
     * @return The total normalized asset amount (always in 18 decimals)
     */
    function totalNormalizedAssets() external view returns (uint256);

    /**
     * @notice Withdraws a specified amount of assets from the vault by controller
     * @dev This function can only be called by the designated controller contract.
     * It's typically used during rebalancing operations to redistribute assets
     * across different vaults.
     * @param asset The address of the asset to withdraw (can be a reward token)
     * @param assets The amount of assets to withdraw (in asset's native decimals)
     * @param receiver The address that will receive the withdrawn assets
     */
    function controllerWithdraw(address asset, uint256 assets, address receiver) external;

    /**
     * @notice Deposits a specified amount of assets into the vault by controller
     * @dev This function can only be called by the designated controller contract.
     * It's typically used to add assets back into the vault following a rebalancing operation.
     * @param assets The amount of assets to deposit (in asset's native decimals)
     */
    function controllerDeposit(uint256 assets) external;
}
