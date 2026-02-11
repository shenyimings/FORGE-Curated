// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IControlledVault } from "../interfaces/IControlledVault.sol";
import { BaseController } from "./BaseController.sol";
import { PriceFeedManager } from "./PriceFeedManager.sol";

/**
 * @title VaultManager
 * @notice Manages vaults within Controller system
 * @dev Abstract contract that handles vault registration, removal, and configuration
 * Uses a linked list structure for efficient vault management and iteration
 * Inherits from BaseController for access control and basic functionality
 */
abstract contract VaultManager is BaseController, PriceFeedManager {
    using Math for uint256;

    /**
     * @notice Role identifier for vault management operations
     */
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    /**
     * @notice Sentinel address used as the head and tail of the vaults linked list
     */
    address public constant SENTINEL_VAULTS = address(0x1);

    /**
     * @notice Emitted when a new vault is added to the system
     */
    event VaultAdded(address indexed vault, address indexed asset);
    /**
     * @notice Emitted when a vault is removed from the system
     */
    event VaultRemoved(address indexed vault);
    /**
     * @notice Emitted when vault settings are updated
     */
    event VaultSettingsUpdated(
        address indexed vault, uint256 maxCapacity, uint256 maxProportionality, uint256 minProportionality
    );
    /**
     * @notice Emitted when the main vault for an asset is updated
     */
    event MainVaultForAssetUpdated(address indexed asset, address indexed oldVault, address indexed newVault);

    /**
     * @notice Thrown when a vault's controller does not match this contract
     */
    error Vault_ControllerMismatch();
    /**
     * @notice Thrown when an invalid vault address is provided
     */
    error Vault_InvalidVault();
    /**
     * @notice Thrown when trying to add a vault for an asset without a price feed
     */
    error Vault_NoPriceFeedForAsset();
    /**
     * @notice Thrown when trying to remove a vault that still contains assets
     */
    error Vault_VaultNotEmpty();
    /**
     * @notice Thrown when the provided previous vault in the linked list is incorrect
     */
    error Vault_InvalidPrevVault();
    /**
     * @notice Thrown when the maximum proportionality exceeds the allowed limit
     */
    error Vault_InvalidMaxProportionality();
    /**
     * @notice Thrown when the minimum proportionality exceeds the allowed limit
     */
    error Vault_InvalidMinProportionality();
    /**
     * @notice Thrown when minimum proportionality is greater than maximum proportionality
     */
    error Vault_MinProportionalityNotLessThanMax();
    /**
     * @notice Thrown when trying to set a vault as the main vault for an asset it already is
     */
    error Vault_AlreadyMainVaultForAsset();

    /**
     * @notice Initializes the VaultManager with an empty vaults linked list
     * @dev Sets up the sentinel vault as the head of the linked list
     * This function should be called during contract initialization
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function __VaultManager_init() internal onlyInitializing {
        _vaults[SENTINEL_VAULTS] = SENTINEL_VAULTS;
    }

    /**
     * @notice Adds a new vault to the system with specified settings
     * @dev The vault is inserted at the beginning of the linked list for O(1) insertion
     * @param vault The address of the vault to add
     * @param settings The configuration settings for the vault
     * @param isMainVaultForAsset If true, sets this vault as the main vault for its asset
     */
    function addVault(
        address vault,
        VaultSettings calldata settings,
        bool isMainVaultForAsset
    )
        external
        onlyRole(VAULT_MANAGER_ROLE)
    {
        require(vault != SENTINEL_VAULTS && vault != address(0) && !isVault(vault), Vault_InvalidVault());
        require(IControlledVault(vault).controller() == address(this), Vault_ControllerMismatch());

        address asset = IControlledVault(vault).asset();
        require(priceFeedExists(asset), Vault_NoPriceFeedForAsset());

        _vaults[vault] = _vaults[SENTINEL_VAULTS];
        _vaults[SENTINEL_VAULTS] = vault;
        _vaultsCount++;
        emit VaultAdded(vault, asset);

        _checkVaultSettings(settings);
        vaultSettings[vault] = settings;
        emit VaultSettingsUpdated(vault, settings.maxCapacity, settings.maxProportionality, settings.minProportionality);

        if (isMainVaultForAsset || _vaultFor[asset] == address(0)) {
            emit MainVaultForAssetUpdated(asset, _vaultFor[asset], vault);
            _vaultFor[asset] = vault;
        }
    }

    /**
     * @notice Removes a vault from the system
     * @dev Removes the vault from the linked list and clears its settings
     * @param vault The address of the vault to remove
     * @param prevVault The address of the vault that precedes this vault in the linked list
     */
    function removeVault(address vault, address prevVault) external onlyRole(VAULT_MANAGER_ROLE) {
        require(isVault(vault), Vault_InvalidVault());
        require(IControlledVault(vault).totalNormalizedAssets() == 0, Vault_VaultNotEmpty());
        require(_vaults[prevVault] == vault, Vault_InvalidPrevVault());

        _vaults[prevVault] = _vaults[vault];
        delete _vaults[vault];
        _vaultsCount--;
        emit VaultRemoved(vault);

        delete vaultSettings[vault];
        emit VaultSettingsUpdated(vault, 0, 0, 0);

        address asset = IControlledVault(vault).asset();
        if (_vaultFor[asset] == vault) {
            emit MainVaultForAssetUpdated(asset, _vaultFor[asset], address(0));
            delete _vaultFor[asset];
        }
    }

    /**
     * @notice Updates the settings for an existing vault
     * @dev Note: It's possible to set settings that are incompatible with the current vault state
     * (e.g., maxCapacity < totalAssets). Such settings may prevent further deposits but
     * should not break existing functionality
     * @param vault The address of the vault to update
     * @param settings The new configuration settings for the vault
     */
    function updateVaultSettings(
        address vault,
        VaultSettings calldata settings
    )
        external
        onlyRole(VAULT_MANAGER_ROLE)
    {
        require(isVault(vault), Vault_InvalidVault());
        _checkVaultSettings(settings);
        vaultSettings[vault] = settings;
        emit VaultSettingsUpdated(vault, settings.maxCapacity, settings.maxProportionality, settings.minProportionality);
    }

    /**
     * @notice Sets the main vault for the asset managed by the specified vault
     * @dev The specified vault must be registered
     * @param vault The address of the vault to set as main for the asset
     */
    function setMainVault(address vault) external onlyRole(VAULT_MANAGER_ROLE) {
        require(isVault(vault), Vault_InvalidVault());
        address asset = IControlledVault(vault).asset();
        require(_vaultFor[asset] != vault, Vault_AlreadyMainVaultForAsset());
        emit MainVaultForAssetUpdated(asset, _vaultFor[asset], vault);
        _vaultFor[asset] = vault;
    }

    /**
     * @notice Checks if an address is a registered vault
     * @param vault The address to check
     * @return True if the address is a registered vault, false otherwise
     */
    function isVault(address vault) public view returns (bool) {
        return vault != SENTINEL_VAULTS && _vaults[vault] != address(0);
    }

    /**
     * @notice Returns an array of all registered vault addresses
     * @dev Iterates through the linked list to collect all vault addresses
     * The order matches the insertion order (most recently added vaults first)
     * @return Array containing all registered vault addresses
     */
    function vaults() public view returns (address[] memory) {
        uint256 vaultCount = _vaultsCount;
        address[] memory vaultList = new address[](vaultCount);
        address currentVault = _vaults[SENTINEL_VAULTS];
        for (uint256 i; i < vaultCount; ++i) {
            vaultList[i] = currentVault;
            currentVault = _vaults[currentVault];
        }
        return vaultList;
    }

    /**
     * @notice Calculates the value of a specific amount of assets held in a vault
     * @param vault The address of the vault
     * @param normalizedAmount The amount of normalized assets to value
     * @return The value of the specified asset amount in normalized decimals
     */
    function _vaultValue(address vault, uint256 normalizedAmount) internal view returns (uint256) {
        return normalizedAmount.mulDiv(getAssetPrice(IControlledVault(vault).asset()), 10 ** NORMALIZED_PRICE_DECIMALS);
    }

    /**
     * @notice Validates vault settings parameters
     * @param settings The vault settings to validate
     */
    function _checkVaultSettings(VaultSettings calldata settings) internal pure {
        require(settings.maxProportionality <= MAX_BPS, Vault_InvalidMaxProportionality());
        require(settings.minProportionality <= MAX_BPS, Vault_InvalidMinProportionality());
        require(settings.minProportionality <= settings.maxProportionality, Vault_MinProportionalityNotLessThanMax());
    }

    /**
     * @notice Retrieves the asset managed by a given vault
     * @param vault The address of the vault
     * @return The address of the asset managed by the vault, or address(0) if not a vault
     */
    function _vaultAsset(address vault) internal view returns (address) {
        return isVault(vault) ? IControlledVault(vault).asset() : address(0);
    }

    struct VaultsOverview {
        address[] vaults;
        uint256[] assets;
        VaultSettings[] settings;
        uint256 totalAssets;
        uint256 totalValue;
    }

    /**
     * @notice Gets a comprehensive overview of all vaults in the system
     * @dev Iterates through all registered vaults to collect their data
     * @param calculateTotalValue If true, calculates the total USD value of all assets
     * @return overview Complete overview struct with vault data and optionally total value
     */
    function _vaultsOverview(bool calculateTotalValue) internal view returns (VaultsOverview memory overview) {
        overview.vaults = vaults();
        uint256 count = overview.vaults.length;
        overview.assets = new uint256[](count);
        overview.settings = new VaultSettings[](count);
        overview.totalAssets = 0;
        overview.totalValue = 0;

        for (uint256 i; i < count; ++i) {
            overview.assets[i] = IControlledVault(overview.vaults[i]).totalNormalizedAssets();
            overview.settings[i] = vaultSettings[overview.vaults[i]];
            overview.totalAssets += overview.assets[i];
            if (calculateTotalValue) {
                overview.totalValue += _vaultValue(overview.vaults[i], overview.assets[i]);
            }
        }
    }
}
