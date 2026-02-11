// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import { IControlledVault } from "../interfaces/IControlledVault.sol";
import { IController } from "../interfaces/IController.sol";
import { IERC7575Vault } from "../interfaces/IERC7575Vault.sol";
import { tryGetAssetDecimals } from "../utils/tryGetAssetDecimals.sol";

/**
 * @title ControlledERC7575Vault
 * @notice A base vault implementation that conforms to ERC7575 standards and can be managed by a controller
 * @dev This contract serves as the foundation for individual asset vaults in the ecosystem.
 * It handles decimal normalization, controller integration, and implements the core ERC7575 vault operations.
 * The vault automatically normalizes all asset amounts to 18 decimals for consistent cross-vault calculations,
 * regardless of the underlying asset's actual decimal places.
 *
 * Key Features:
 * - ERC7575 compliant vault operations (deposit, mint, withdraw, redeem)
 * - Automatic decimal normalization to 18 decimals
 * - Controller-managed rebalancing capabilities
 * - Extensible hooks for custom vault implementations
 * - Safe asset transfers using OpenZeppelin's SafeERC20
 */
contract ControlledERC7575Vault is ReentrancyGuardTransient, IERC7575Vault, IControlledVault {
    using SafeERC20 for IERC20;

    /**
     * @notice The standardized decimal precision used for all normalized asset calculations
     */
    uint8 public constant NORMALIZED_ASSET_DECIMALS = 18;

    /**
     * @notice The underlying ERC20 asset managed by this vault
     */
    IERC20 internal immutable _asset;
    /**
     * @notice The controller contract that manages this vault
     */
    IController internal immutable _controller;
    /**
     * @notice The decimal offset used to normalize asset amounts to 18 decimals
     */
    uint8 internal immutable _decimalsOffset;

    /**
     * @notice Thrown when attempting to create a vault with a zero address asset
     */
    error ZeroAsset();
    /**
     * @notice Thrown when attempting to create a vault with a zero address controller
     */
    error ZeroController();
    /**
     * @notice Thrown when the asset's decimals cannot be fetched
     */
    error NoDecimals();
    /**
     * @notice Thrown when the underlying asset has more decimals than the normalized standard
     */
    error AssetDecimalsTooHigh();
    /**
     * @notice Thrown when attempting to deposit or withdraw zero assets or shares
     */
    error ZeroAssetsOrShares();

    /**
     * @notice Constructs a new ControlledERC7575Vault
     * @dev Initializes the vault with the specified asset and controller. Automatically determines
     * the decimal offset needed to normalize asset amounts to 18 decimals.
     *
     * Requirements:
     * - `asset_` must not be the zero address
     * - `controller_` must not be the zero address
     * - asset decimals must not exceed 18
     *
     * @param asset_ The ERC20 token that this vault will manage
     * @param controller_ The controller contract that will manage this vault
     */
    constructor(IERC20 asset_, IController controller_) {
        require(address(asset_) != address(0), ZeroAsset());
        require(address(controller_) != address(0), ZeroController());

        _asset = asset_;
        _controller = controller_;

        (bool success, uint8 assetDecimals) = tryGetAssetDecimals(asset_);
        require(success, NoDecimals());
        require(assetDecimals <= NORMALIZED_ASSET_DECIMALS, AssetDecimalsTooHigh());
        _decimalsOffset = NORMALIZED_ASSET_DECIMALS - assetDecimals;
    }

    /**
     * @notice Returns the address of the share token
     * @dev All vaults share the same share token as their share representation
     * @return The address of the share token contract managed by the controller
     */
    function share() external view returns (address) {
        return _controller.share();
    }

    /**
     * @notice Returns the address of the underlying asset token
     * @dev Each vault manages a single underlying asset token
     * @return The address of the underlying asset ERC20 contract
     */
    function asset() external view override(IControlledVault, IERC7575Vault) returns (address) {
        return address(_asset);
    }

    /**
     * @notice Returns the total amount of underlying assets managed by the vault
     * @dev Includes both assets held directly in the vault and any additional assets
     * managed through strategies or other mechanisms (via `_additionalOwnedAssets`)
     * @return The total amount of assets in the asset's native decimal precision
     */
    function totalAssets() public view returns (uint256) {
        return _asset.balanceOf(address(this)) + _additionalOwnedAssets();
    }

    /**
     * @notice Returns the address of the controller contract that manages this vault
     * @dev The controller has special privileges to perform operations like rebalancing
     * @return The address of the controller contract
     */
    function controller() external view returns (address) {
        return address(_controller);
    }

    /**
     * @notice Returns the total amount of normalized assets held by the vault
     * @dev Normalized assets are standardized to 18 decimals regardless of the underlying
     * asset's actual decimal places. Used for consistent cross-vault calculations
     * @return The total normalized asset amount (always in 18 decimals)
     */
    function totalNormalizedAssets() external view returns (uint256) {
        return _upscaleDecimals(totalAssets());
    }

    /**
     * @notice Converts an amount of assets to the equivalent amount of shares
     * @dev In this implementation, shares are 1:1 with normalized assets (18 decimals) due to
     * missing dynamic pricing context that would be required for more complex calculations
     * @param assets The amount of assets to convert (in asset's native decimals)
     * @return The equivalent amount of shares (normalized to 18 decimals)
     */
    function convertToShares(uint256 assets) external view returns (uint256) {
        return _upscaleDecimals(assets);
    }

    /**
     * @notice Converts an amount of shares to the equivalent amount of assets
     * @dev In this implementation, shares are 1:1 with normalized assets (18 decimals) due to
     * missing dynamic pricing context that would be required for more complex calculations
     * @param shares The amount of shares to convert (normalized 18 decimals)
     * @return The equivalent amount of assets (in asset's native decimals)
     */
    function convertToAssets(uint256 shares) external view returns (uint256) {
        return _downscaleDecimals(shares, Math.Rounding.Floor);
    }

    /**
     * @notice Deposits assets into the vault and mints shares to the receiver
     * @dev Transfers assets from the caller, normalizes the amount, and delegates to the controller
     * for share minting. The controller handles the actual share token minting and any
     * cross-vault considerations like dynamic pricing.
     *
     * Requirements:
     * - Caller must have approved this contract to spend `assets` amount
     * - `assets` must not exceed the maximum deposit limit
     *
     * Emits:
     * - {Deposit} event with the deposit details
     *
     * @param assets The amount of assets to deposit (in asset's native decimals)
     * @param receiver The address that will receive the minted shares
     * @return shares The amount of shares minted (normalized to 18 decimals)
     */
    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        shares = _controller.deposit(_upscaleDecimals(assets), receiver);
        _deposit(receiver, assets, shares);
    }

    /**
     * @notice Mints a specific amount of shares and deposits the required assets
     * @dev Calculates the required assets through the controller, then transfers assets
     * from the caller. The controller handles the actual share token minting.
     * Assets are calculated using ceiling rounding, which ensures that for any non-zero
     * shares input, the calculated assets will also be non-zero, preventing free share minting.
     *
     * Requirements:
     * - Caller must have approved this contract to spend the calculated `assets` amount
     * - `shares` must not exceed the maximum mint limit
     *
     * Emits:
     * - {Deposit} event with the deposit details
     *
     * @param shares The amount of shares to mint (normalized to 18 decimals)
     * @param receiver The address that will receive the minted shares
     * @return assets The amount of assets deposited (in asset's native decimals)
     */
    function mint(uint256 shares, address receiver) external nonReentrant returns (uint256 assets) {
        assets = _downscaleDecimals(_controller.mint(shares, receiver), Math.Rounding.Ceil);
        _deposit(receiver, assets, shares);
    }

    /**
     * @notice Withdraws a specific amount of assets and burns the required shares
     * @dev Burns shares from the owner through the controller, then transfers assets
     * to the receiver. Handles any necessary asset rebalancing through hooks.
     *
     * Requirements:
     * - If caller is not the owner, they must have sufficient allowance
     * - `assets` must not exceed the maximum withdrawal limit
     * - Vault must have sufficient available assets
     *
     * Emits:
     * - {Withdraw} event with the withdrawal details
     *
     * @param assets The amount of assets to withdraw (in asset's native decimals)
     * @param receiver The address that will receive the withdrawn assets
     * @param owner The address that owns the shares being burned
     * @return shares The amount of shares burned (normalized to 18 decimals)
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        external
        nonReentrant
        returns (uint256 shares)
    {
        shares = _controller.withdraw(_upscaleDecimals(assets), msg.sender, owner);
        _withdraw(receiver, owner, assets, shares);
    }

    /**
     * @notice Redeems a specific amount of shares for assets
     * @dev Burns shares from the owner through the controller, calculates the assets
     * to withdraw, then transfers assets to the receiver.
     *
     * Requirements:
     * - If caller is not the owner, they must have sufficient allowance
     * - `shares` must not exceed the maximum redemption limit
     * - Vault must have sufficient available assets
     *
     * Emits:
     * - {Withdraw} event with the withdrawal details
     *
     * @param shares The amount of shares to redeem (normalized to 18 decimals)
     * @param receiver The address that will receive the withdrawn assets
     * @param owner The address that owns the shares being burned
     * @return assets The amount of assets withdrawn (in asset's native decimals)
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        external
        nonReentrant
        returns (uint256 assets)
    {
        assets = _downscaleDecimals(_controller.redeem(shares, msg.sender, owner), Math.Rounding.Floor);
        _withdraw(receiver, owner, assets, shares);
    }

    /**
     * @notice Previews the amount of shares that would be minted for a given asset deposit
     * @dev Simulates a deposit operation without executing it. Normalizes the asset amount
     * and delegates to the controller for share calculation based on current pricing.
     * @param assets The amount of assets to preview depositing (in asset's native decimals)
     * @return shares The amount of shares that would be minted (normalized to 18 decimals)
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        return _controller.previewDeposit(_upscaleDecimals(assets));
    }

    /**
     * @notice Previews the amount of assets required to mint a given amount of shares
     * @dev Simulates a mint operation without executing it. Delegates to the controller
     * for asset calculation based on current pricing, then denormalizes the result.
     * @param shares The amount of shares to preview minting (normalized to 18 decimals)
     * @return assets The amount of assets that would be required (in asset's native decimals)
     */
    function previewMint(uint256 shares) external view returns (uint256 assets) {
        return _downscaleDecimals(_controller.previewMint(shares), Math.Rounding.Ceil);
    }

    /**
     * @notice Previews the amount of shares that would be burned for a given asset withdrawal
     * @dev Simulates a withdrawal operation without executing it. Normalizes the asset amount
     * and delegates to the controller for share calculation based on current pricing.
     * @param assets The amount of assets to preview withdrawing (in asset's native decimals)
     * @return shares The amount of shares that would be burned (normalized to 18 decimals)
     */
    function previewWithdraw(uint256 assets) external view returns (uint256 shares) {
        return _controller.previewWithdraw(_upscaleDecimals(assets));
    }

    /**
     * @notice Previews the amount of assets that would be withdrawn for a given share redemption
     * @dev Simulates a redemption operation without executing it. Delegates to the controller
     * for asset calculation based on current pricing, then denormalizes the result.
     * @param shares The amount of shares to preview redeeming (normalized to 18 decimals)
     * @return assets The amount of assets that would be withdrawn (in asset's native decimals)
     */
    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        return _downscaleDecimals(_controller.previewRedeem(shares), Math.Rounding.Floor);
    }

    /**
     * @notice Returns the maximum amount of assets that can be deposited for a given receiver
     * @dev Delegates to the controller which considers protocol-wide limits, vault capacity,
     * and any receiver-specific restrictions. Result is denormalized to asset's native decimals.
     * @param receiver The address that would receive the minted shares
     * @return assets The maximum amount of assets that can be deposited (in asset's native decimals)
     */
    function maxDeposit(address receiver) external view returns (uint256 assets) {
        return _downscaleDecimals(_controller.maxDeposit(receiver), Math.Rounding.Floor);
    }

    /**
     * @notice Returns the maximum amount of shares that can be minted for a given receiver
     * @dev Delegates to the controller which considers protocol-wide limits, vault capacity,
     * and any receiver-specific restrictions.
     * @param receiver The address that would receive the minted shares
     * @return shares The maximum amount of shares that can be minted (normalized to 18 decimals)
     */
    function maxMint(address receiver) external view returns (uint256 shares) {
        return _controller.maxMint(receiver);
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn by a given owner
     * @dev Considers both the controller's limits and the vault's available asset liquidity.
     * The available assets include both vault balance and any immediately accessible
     * assets from strategies.
     * @param owner The address that owns the shares
     * @return assets The maximum amount of assets that can be withdrawn (in asset's native decimals)
     */
    function maxWithdraw(address owner) external view returns (uint256 assets) {
        return
            _downscaleDecimals(
                _controller.maxWithdraw(owner, _upscaleDecimals(_availableAssets())), Math.Rounding.Floor
            );
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed by a given owner
     * @dev Considers both the controller's limits and the vault's available asset liquidity.
     * The available assets limit how many shares can actually be redeemed for assets.
     * @param owner The address that owns the shares
     * @return shares The maximum amount of shares that can be redeemed (normalized to 18 decimals)
     */
    function maxRedeem(address owner) external view returns (uint256 shares) {
        return _controller.maxRedeem(owner, _upscaleDecimals(_availableAssets()));
    }

    /**
     * @notice Withdraws assets from the vault by controller
     * @dev This function can only be called by the designated controller contract.
     * It's used during rebalancing operations to redistribute assets across
     * different vaults in the protocol. The function executes any necessary
     * pre-withdrawal hooks.
     *
     * Requirements:
     * - Can only be called by the controller contract
     * - Vault must have sufficient assets to transfer
     *
     * Emits:
     * - {ControllerWithdraw} event with the withdrawn asset amount
     *
     * @param asset_ The address of the asset to withdraw (can be a reward token)
     * @param assets The amount of assets to withdraw (in asset's native decimals)
     * @param receiver The address that will receive the withdrawn assets
     *
     * @custom:security Access restricted to controller only to prevent unauthorized asset drainage
     */
    function controllerWithdraw(address asset_, uint256 assets, address receiver) external nonReentrant {
        require(msg.sender == address(_controller), CallerNotController());
        if (asset_ == address(_asset)) _beforeWithdraw(assets);
        IERC20(asset_).safeTransfer(receiver, assets);
        emit ControllerWithdraw(asset_, assets, receiver);
    }

    /**
     * @notice Deposits assets into the vault by controller
     * @dev This function can only be called by the designated controller contract.
     * It's used during rebalancing operations to allocate assets that are already
     * present in the vault. The controller is expected to transfer the assets into
     * the vault before calling this function. The function executes any necessary
     * post-deposit hooks to properly allocate the assets.
     *
     * Requirements:
     * - Can only be called by the controller contract
     *
     * Emits:
     * - {ControllerDeposit} event with the deposited asset amount
     *
     * @param assets The amount of assets to deposit (in asset's native decimals)
     *
     * @custom:security Access restricted to controller only to prevent unauthorized asset manipulation
     */
    function controllerDeposit(uint256 assets) external nonReentrant {
        require(msg.sender == address(_controller), CallerNotController());
        _afterDeposit(assets);
        emit ControllerDeposit(assets);
    }

    /**
     * @notice Internal function to handle asset deposits and emit events
     * @dev Transfers assets from the caller to the vault, executes post-deposit hooks,
     * and emits the deposit event. Used by both deposit and mint functions.
     *
     * @param receiver The address that received the minted shares
     * @param assets The amount of assets deposited (in asset's native decimals)
     * @param shares The amount of shares minted (normalized to 18 decimals)
     *
     * @custom:security Uses SafeERC20 for secure token transfers
     */
    function _deposit(address receiver, uint256 assets, uint256 shares) private {
        require(assets > 0 && shares > 0, ZeroAssetsOrShares());
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        _afterDeposit(assets);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Internal function to handle asset withdrawals and emit events
     * @dev Executes pre-withdrawal hooks, transfers assets to the receiver,
     * and emits the withdrawal event. Used by both withdraw and redeem functions.
     *
     * @param receiver The address that will receive the withdrawn assets
     * @param owner The address that owns the shares being burned
     * @param assets The amount of assets withdrawn (in asset's native decimals)
     * @param shares The amount of shares burned (normalized to 18 decimals)
     *
     * @custom:security Uses SafeERC20 for secure token transfers
     */
    function _withdraw(address receiver, address owner, uint256 assets, uint256 shares) private {
        require(assets > 0 && shares > 0, ZeroAssetsOrShares());
        _beforeWithdraw(assets);
        _asset.safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Calculates the total amount of assets immediately available for withdrawal
     * @dev Includes assets held directly in the vault plus any additional assets
     * that can be quickly accessed (e.g., from liquid strategies)
     * @return The total amount of immediately available assets (in asset's native decimals)
     */
    function _availableAssets() private view returns (uint256) {
        return _asset.balanceOf(address(this)) + _additionalAvailableAssets();
    }

    /**
     * @notice Converts an asset amount to normalized decimals (18 decimals)
     * @dev Multiplies by 10^decimalsOffset to scale up from asset's native decimals
     * to the standardized 18 decimal format used throughout the protocol
     * @param value The amount in asset's native decimals
     * @return The amount scaled up to 18 decimals
     */
    function _upscaleDecimals(uint256 value) private view returns (uint256) {
        return value * 10 ** _decimalsOffset;
    }

    /**
     * @notice Converts a normalized amount back to the asset's native decimals
     * @dev Divides by 10^decimalsOffset to scale down from the standardized
     * 18 decimal format to the asset's actual decimal precision
     * @param value The amount in normalized 18 decimals
     * @return The amount scaled down to asset's native decimals
     */
    function _downscaleDecimals(uint256 value, Math.Rounding rounding) private view returns (uint256) {
        uint256 divisor = 10 ** _decimalsOffset;
        uint256 result = value / divisor;
        if (rounding == Math.Rounding.Ceil && value % divisor > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @notice Hook to calculate additional assets owned by the vault beyond its direct balance
     * @dev This virtual function allows child contracts to include assets deployed to strategies,
     * lending protocols, or other yield-generating mechanisms in the total asset calculation.
     * The base implementation returns 0, assuming no additional assets.
     * @return The amount of additional assets owned by the vault (in asset's native decimals)
     *
     * @custom:override Child contracts should override this to include strategy assets
     */
    function _additionalOwnedAssets() internal view virtual returns (uint256) {
        return 0;
    }

    /**
     * @notice Hook to calculate additional assets immediately available for withdrawal
     * @dev This virtual function allows child contracts to include liquid assets from strategies
     * or other sources that can be quickly accessed for withdrawals without requiring
     * complex unwinding operations. The base implementation returns 0.
     * @return The amount of additional available assets (in asset's native decimals)
     *
     * @custom:override Child contracts should override this to include liquid strategy assets
     */
    function _additionalAvailableAssets() internal view virtual returns (uint256) {
        return 0;
    }

    /**
     * @notice Hook executed before asset withdrawals to prepare the vault
     * @dev This virtual function allows child contracts to implement custom logic before
     * withdrawals, such as unwinding positions from strategies, ensuring sufficient
     * liquidity, or updating internal accounting. The base implementation is empty.
     * @param assets The amount of assets about to be withdrawn (in asset's native decimals)
     *
     * @custom:override Child contracts can override this to implement withdrawal preparation logic
     */
    function _beforeWithdraw(uint256 assets) internal virtual { }

    /**
     * @notice Hook executed after asset deposits to process the deposited funds
     * @dev This virtual function allows child contracts to implement custom logic after
     * deposits, such as deploying assets to strategies, updating allocations, or
     * performing other post-deposit operations. The base implementation is empty.
     * @param assets The amount of assets that were deposited (in asset's native decimals)
     *
     * @custom:override Child contracts can override this to implement post-deposit logic
     */
    function _afterDeposit(uint256 assets) internal virtual { }
}
