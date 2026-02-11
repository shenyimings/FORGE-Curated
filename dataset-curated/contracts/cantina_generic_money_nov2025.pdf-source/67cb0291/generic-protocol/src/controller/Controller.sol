// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { AccountingLogic } from "./AccountingLogic.sol";
import { PeripheryManager, ISwapper, IYieldDistributor } from "./PeripheryManager.sol";
import { PriceFeedManager } from "./PriceFeedManager.sol";
import { RebalancingManager } from "./RebalancingManager.sol";
import { VaultLimitsLogic } from "./VaultLimitsLogic.sol";
import { VaultManager } from "./VaultManager.sol";
import { YieldManager } from "./YieldManager.sol";
import { EmergencyManager } from "./EmergencyManager.sol";
import { ConfigManager } from "./ConfigManager.sol";
import { RewardsManager } from "./RewardsManager.sol";
import { IController } from "../interfaces/IController.sol";
import { IGenericShare } from "../interfaces/IGenericShare.sol";

/**
 * @title Controller
 * @notice Core controller contract that manages vaults, shares, and protocol operations
 * @dev Inherits from multiple manager contracts to provide comprehensive vault management functionality
 * This contract handles ERC7575 vault operations, price feeds, fee management, rebalancing,
 * yield distribution, and periphery integrations
 */
contract Controller is
    IController,
    PriceFeedManager,
    VaultManager,
    ConfigManager,
    PeripheryManager,
    AccountingLogic,
    RebalancingManager,
    VaultLimitsLogic,
    YieldManager,
    EmergencyManager,
    RewardsManager
{
    using Math for uint256;

    /**
     * @notice Thrown when admin address is zero during initialization
     */
    error Controller_ZeroAdmin();
    /**
     * @notice Thrown when share address is zero during initialization
     */
    error Controller_ZeroShare();
    /**
     * @notice Thrown when deposit amount exceeds maximum allowed limit
     */
    error Controller_DepositExceedsMax();
    /**
     * @notice Thrown when mint amount exceeds maximum allowed limit
     */
    error Controller_MintExceedsMax();
    /**
     * @notice Thrown when withdrawal amount exceeds maximum allowed limit
     */
    error Controller_WithdrawExceedsMax();
    /**
     * @notice Thrown when redeem amount exceeds maximum allowed limit
     */
    error Controller_RedeemExceedsMax();
    /**
     * @notice Thrown when caller is not a registered vault
     */
    error Controller_CallerNotVault();
    /**
     * @notice Thrown when caller is not the main vault for an asset
     */
    error Controller_CallerNotMainVault();

    /**
     * @notice Ensures only registered vaults can call the function
     */
    modifier onlyVault() {
        _onlyVault();
        _;
    }

    function _onlyVault() internal view {
        require(isVault(msg.sender), Controller_CallerNotVault());
    }

    /**
     * @notice Ensures only the main vault for an asset can call the function
     */
    modifier onlyMainVault() {
        _onlyMainVault();
        _;
    }

    function _onlyMainVault() internal view {
        _onlyVault();
        require(_vaultFor[_vaultAsset(msg.sender)] == msg.sender, Controller_CallerNotMainVault());
    }

    /**
     * @notice Constructor that disables initializers to prevent direct initialization
     * @dev Uses OpenZeppelin's initializer pattern for upgradeable contracts
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the Controller with required parameters
     * @dev Can only be called once due to initializer modifier. Reverts if admin or share address is zero.
     * @param admin Address that will receive admin role for access control
     * @param share_ The address of protocol shares
     * @param rewardsCollector_ Address that will collect rewards from yield optimization
     * @param swapper_ Swapper contract for token exchanges
     * @param yieldDistributor_ Contract for distributing yield to stakeholders
     */
    function initialize(
        address admin,
        IGenericShare share_,
        address rewardsCollector_,
        ISwapper swapper_,
        IYieldDistributor yieldDistributor_
    )
        external
        initializer
    {
        require(admin != address(0), Controller_ZeroAdmin());
        require(address(share_) != address(0), Controller_ZeroShare());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _share = share_;

        __PriceFeedManager_init();
        __VaultManager_init();
        __ConfigManager_init(rewardsCollector_);
        __PeripheryManager_init(swapper_, yieldDistributor_);
        __RebalancingManager_init();
        __YieldManager_init();
        __EmergencyManager_init();
        __RewardsManager_init();
    }

    /**
     * @notice Returns the address of the share token contract
     * @return The address of the share token contract
     */
    function share() external view returns (address) {
        return address(_share);
    }

    /**
     * @notice Returns the main vault address for a given asset
     * @param asset The address of the asset to query
     * @return The address of the main vault for the specified asset
     */
    function vaultFor(address asset) external view returns (address) {
        return _vaultFor[asset];
    }

    // ========================================
    // ERC4626 MAX FUNCTIONS
    // ========================================

    /**
     * @notice Returns the maximum amount of assets that can be deposited for a receiver
     * @dev Only callable by main vaults, uses current vault limits and overview
     * @return The maximum deposit amount in normalized asset units
     */
    function maxDeposit(
        address /* receiver */
    )
        public
        view
        onlyMainVault
        returns (uint256)
    {
        address vault = msg.sender;
        return _maxDepositLimit(_vaultsOverview(false), vault);
    }

    /**
     * @notice Returns the maximum amount of shares that can be minted for a receiver
     * @dev Only callable by main vaults, converts max deposit limit to shares
     * @return The maximum mint amount in shares
     */
    function maxMint(
        address /* receiver */
    )
        public
        view
        onlyMainVault
        returns (uint256)
    {
        address vault = msg.sender;
        uint256 maxAssets = _maxDepositLimit(_vaultsOverview(false), vault);
        if (maxAssets == type(uint256).max) return maxAssets;

        return _convertToShares({
            normalizedAssets: maxAssets,
            assetPrice: assetDepositPrice(_vaultAsset(vault)),
            sharePrice: shareDepositPrice(),
            rounding: Math.Rounding.Floor
        });
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn by an owner
     * @dev Only callable by vaults, considers both vault limits and owner's balance
     * @param owner The address of the share holder
     * @param availableAssets The amount of assets currently available in the vault
     * @return The maximum withdrawal amount in normalized asset units
     */
    function maxWithdraw(address owner, uint256 availableAssets) public view onlyVault returns (uint256) {
        address vault = msg.sender;
        uint256 maxAssets = _maxWithdrawLimit(_vaultsOverview(false), vault).min(availableAssets);
        uint256 ownedAssets = _convertToAssets({
            shares: _share.balanceOf(owner),
            assetPrice: assetRedemptionPrice(_vaultAsset(vault)),
            sharePrice: shareRedemptionPrice(),
            rounding: Math.Rounding.Floor
        });
        return ownedAssets.min(maxAssets);
    }

    /**
     * @notice Returns the maximum number of shares that can be redeemed by an owner
     * @dev Only callable by vaults, considers both vault limits and owner's balance
     * @param owner The address of the share holder
     * @param availableAssets The amount of assets currently available in the vault
     * @return The maximum redeem amount in shares
     */
    function maxRedeem(address owner, uint256 availableAssets) public view onlyVault returns (uint256) {
        address vault = msg.sender;
        uint256 maxAssets = _maxWithdrawLimit(_vaultsOverview(false), vault).min(availableAssets);
        uint256 maxShares = _convertToShares({
            normalizedAssets: maxAssets,
            assetPrice: assetRedemptionPrice(_vaultAsset(vault)),
            sharePrice: shareRedemptionPrice(),
            rounding: Math.Rounding.Floor
        });
        return _share.balanceOf(owner).min(maxShares);
    }

    // ========================================
    // ERC4626 PREVIEW FUNCTIONS
    // ========================================

    /**
     * @notice Simulates the effects of a deposit at the current block
     * @dev Only callable by main vaults, uses deposit pricing
     * @param normalizedAssets The amount of normalized assets to deposit
     * @return shares The amount of shares that would be received
     */
    function previewDeposit(uint256 normalizedAssets) public view onlyMainVault returns (uint256 shares) {
        return _convertToShares({
            normalizedAssets: normalizedAssets,
            assetPrice: assetDepositPrice(_vaultAsset(msg.sender)),
            sharePrice: shareDepositPrice(),
            rounding: Math.Rounding.Floor
        });
    }

    /**
     * @notice Simulates the effects of a mint at the current block
     * @dev Only callable by main vaults, uses deposit pricing with ceiling rounding
     * @param shares The amount of shares to mint
     * @return normalizedAssets The amount of normalized assets that would be required
     */
    function previewMint(uint256 shares) public view onlyMainVault returns (uint256 normalizedAssets) {
        return _convertToAssets({
            shares: shares,
            assetPrice: assetDepositPrice(_vaultAsset(msg.sender)),
            sharePrice: shareDepositPrice(),
            rounding: Math.Rounding.Ceil
        });
    }

    /**
     * @notice Simulates the effects of a withdrawal at the current block
     * @dev Only callable by vaults, uses redemption pricing with ceiling rounding
     * @param normalizedAssets The amount of normalized assets to withdraw
     * @return shares The amount of shares that would be burned
     */
    function previewWithdraw(uint256 normalizedAssets) public view onlyVault returns (uint256 shares) {
        return _convertToShares({
            normalizedAssets: normalizedAssets,
            assetPrice: assetRedemptionPrice(_vaultAsset(msg.sender)),
            sharePrice: shareRedemptionPrice(),
            rounding: Math.Rounding.Ceil
        });
    }

    /**
     * @notice Simulates the effects of a redemption at the current block
     * @dev Only callable by vaults, uses redemption pricing
     * @param shares The amount of shares to redeem
     * @return normalizedAssets The amount of normalized assets that would be withdrawn
     */
    function previewRedeem(uint256 shares) public view onlyVault returns (uint256 normalizedAssets) {
        return _convertToAssets({
            shares: shares,
            assetPrice: assetRedemptionPrice(_vaultAsset(msg.sender)),
            sharePrice: shareRedemptionPrice(),
            rounding: Math.Rounding.Floor
        });
    }

    // ========================================
    // ERC4626 FUNCTIONS
    // ========================================

    /**
     * @notice Deposits normalized assets and mints shares to receiver
     * @dev Only callable by main vaults when not paused, validates deposit doesn't exceed limits
     * @param normalizedAssets The amount of normalized assets to deposit
     * @param receiver The address that will receive the minted shares
     * @return shares The amount of shares minted to the receiver
     */
    function deposit(
        uint256 normalizedAssets,
        address receiver
    )
        public
        onlyMainVault
        notPaused
        returns (uint256 shares)
    {
        address vault = msg.sender;
        VaultsOverview memory overview = _vaultsOverview({ calculateTotalValue: false });

        require(normalizedAssets <= _maxDepositLimit(overview, vault), Controller_DepositExceedsMax());
        shares = _convertToShares({
            normalizedAssets: normalizedAssets,
            assetPrice: assetDepositPrice(_vaultAsset(vault)),
            sharePrice: shareDepositPrice(),
            rounding: Math.Rounding.Floor
        });

        _share.mint(receiver, shares);
    }

    /**
     * @notice Mints exact amount of shares to receiver for required assets
     * @dev Only callable by main vaults when not paused, validates required assets don't exceed limits
     * @param shares The amount of shares to mint
     * @param receiver The address that will receive the minted shares
     * @return normalizedAssets The amount of normalized assets required for minting
     */
    function mint(
        uint256 shares,
        address receiver
    )
        public
        onlyMainVault
        notPaused
        returns (uint256 normalizedAssets)
    {
        address vault = msg.sender;
        VaultsOverview memory overview = _vaultsOverview({ calculateTotalValue: false });

        normalizedAssets = _convertToAssets({
            shares: shares,
            assetPrice: assetDepositPrice(_vaultAsset(vault)),
            sharePrice: shareDepositPrice(),
            rounding: Math.Rounding.Ceil
        });
        require(normalizedAssets <= _maxDepositLimit(overview, vault), Controller_MintExceedsMax());

        _share.mint(receiver, shares);
    }

    /**
     * @notice Burns shares from owner and withdraws exact amount of normalized assets
     * @dev Only callable by vaults when not paused, validates withdrawal doesn't exceed limits and owner balance
     * @param normalizedAssets The amount of normalized assets to withdraw
     * @param spender The address authorized to spend the owner's shares
     * @param owner The address that owns the shares to be burned
     * @return shares The amount of shares burned from the owner
     */
    function withdraw(
        uint256 normalizedAssets,
        address spender,
        address owner
    )
        public
        onlyVault
        notPaused
        returns (uint256 shares)
    {
        address vault = msg.sender;
        VaultsOverview memory overview = _vaultsOverview({ calculateTotalValue: true });

        require(normalizedAssets <= _maxWithdrawLimit(overview, vault), Controller_WithdrawExceedsMax());
        shares = _convertToShares({
            normalizedAssets: normalizedAssets,
            assetPrice: assetRedemptionPrice(_vaultAsset(vault)),
            sharePrice: _shareRedemptionPrice(overview.totalValue),
            rounding: Math.Rounding.Ceil
        });
        require(shares <= _share.balanceOf(owner), Controller_WithdrawExceedsMax());

        _share.burn(owner, spender, shares);
    }

    /**
     * @notice Burns exact amount of shares from owner and withdraws corresponding assets
     * @dev Only callable by vaults when not paused, validates owner has sufficient balance and withdrawal doesn't
     * exceed limits
     * @param shares The amount of shares to redeem
     * @param spender The address authorized to spend the owner's shares
     * @param owner The address that owns the shares to be burned
     * @return normalizedAssets The amount of normalized assets withdrawn
     */
    function redeem(
        uint256 shares,
        address spender,
        address owner
    )
        public
        onlyVault
        notPaused
        returns (uint256 normalizedAssets)
    {
        address vault = msg.sender;
        VaultsOverview memory overview = _vaultsOverview({ calculateTotalValue: true });

        require(shares <= _share.balanceOf(owner), Controller_RedeemExceedsMax());
        normalizedAssets = _convertToAssets({
            shares: shares,
            assetPrice: assetRedemptionPrice(_vaultAsset(vault)),
            sharePrice: _shareRedemptionPrice(overview.totalValue),
            rounding: Math.Rounding.Floor
        });
        require(normalizedAssets <= _maxWithdrawLimit(overview, vault), Controller_RedeemExceedsMax());

        _share.burn(owner, spender, shares);
    }
}
