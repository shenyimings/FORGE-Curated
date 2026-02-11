// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";

import {MulticallUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/MulticallUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IVault} from "@src//IVault.sol";
import {Auth} from "@src/Auth.sol";
import {DEFAULT_ADMIN_ROLE, GUARDIAN_ROLE, VAULT_MANAGER_ROLE} from "@src/Auth.sol";

/// @title BaseVault
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice Abstract base contract for all vaults in the Size Meta Vault system
/// @dev Provides common functionality including ERC4626 compliance, access control, and upgradeability
abstract contract BaseVault is IVault, ERC4626Upgradeable, ERC20PermitUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, MulticallUpgradeable, UUPSUpgradeable {
  // STORAGE
  /// @custom:storage-location erc7201:size.storage.BaseVault
  struct BaseVaultStorage {
    Auth _auth;
    uint256 _totalAssetsCap;
  }

  // keccak256(abi.encode(uint256(keccak256("size.storage.BaseVault")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant BaseVaultStorageLocation = 0x404a41806115f4e0ed08eb395c0045722d1875ff8794e55da96cf8391291c100;

  function _getBaseVaultStorage() private pure returns (BaseVaultStorage storage $) {
    assembly {
      $.slot := BaseVaultStorageLocation
    }
  }

  // ERRORS
  error NullAddress();
  error NullAmount();

  // EVENTS
  event AuthSet(address indexed auth);
  event TotalAssetsCapSet(uint256 indexed totalAssetsCapBefore, uint256 indexed totalAssetsCapAfter);
  event VaultStatus(uint256 totalShares, uint256 totalAssets);

  // CONSTRUCTOR / INITIALIZER
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the BaseVault with necessary parameters
  /// @dev Sets up all inherited contracts and makes the first deposit to prevent inflation attacks
  function initialize(Auth auth_, IERC20 asset_, string memory name_, string memory symbol_, address fundingAccount_, uint256 firstDepositAmount_) public virtual initializer {
    __ERC4626_init(asset_);
    __ERC20_init(name_, symbol_);
    __ERC20Permit_init(name_);
    __ReentrancyGuard_init();
    __Pausable_init();
    __Multicall_init();
    __UUPSUpgradeable_init();

    if (address(auth_) == address(0)) revert NullAddress();
    if (firstDepositAmount_ == 0) revert NullAmount();

    BaseVaultStorage storage $ = _getBaseVaultStorage();
    $._auth = auth_;
    emit AuthSet(address(auth_));

    _setTotalAssetsCap(type(uint256).max);

    _firstDeposit(fundingAccount_, firstDepositAmount_);
  }

  // MODIFIERS
  /// @notice Modifier to restrict function access to addresses with specific roles
  /// @dev Reverts if the caller doesn't have the required role
  modifier onlyAuth(bytes32 role) {
    if (!auth().hasRole(role, msg.sender)) revert IAccessControl.AccessControlUnauthorizedAccount(msg.sender, role);
    _;
  }

  /// @notice Modifier to ensure the contract is not paused
  /// @dev Checks both local pause state and global pause state from Auth
  modifier notPaused() {
    if (_isPaused()) revert EnforcedPause();
    _;
  }

  /// @notice Modifier to emit the vault status
  /// @dev Emits the vault status after the function is executed
  modifier emitVaultStatus() {
    _;
    emit VaultStatus(totalSupply(), totalAssets());
  }

  // INTERNAL/PRIVATE
  /// @notice Authorizes contract upgrades
  /// @dev Only addresses with DEFAULT_ADMIN_ROLE can authorize upgrades
  function _authorizeUpgrade(address newImplementation) internal override onlyAuth(DEFAULT_ADMIN_ROLE) {}

  /// @notice Pauses the vault
  /// @dev Only addresses with GUARDIAN_ROLE can pause the vault
  function pause() external onlyAuth(GUARDIAN_ROLE) {
    _pause();
  }

  /// @notice Unpauses the vault
  /// @dev Only addresses with VAULT_MANAGER_ROLE can unpause the vault
  function unpause() external onlyAuth(VAULT_MANAGER_ROLE) {
    _unpause();
  }

  /// @notice Sets the maximum total assets of the vault
  /// @dev Only callable by the auth contract
  /// @dev Lowering the total assets cap does not affect existing deposited assets
  function setTotalAssetsCap(uint256 totalAssetsCap_) external onlyAuth(VAULT_MANAGER_ROLE) {
    _setTotalAssetsCap(totalAssetsCap_);
  }

  /// @notice Sets the maximum total assets of the vault
  function _setTotalAssetsCap(uint256 totalAssetsCap_) private {
    BaseVaultStorage storage $ = _getBaseVaultStorage();
    uint256 oldTotalAssetsCap = $._totalAssetsCap;
    $._totalAssetsCap = totalAssetsCap_;
    emit TotalAssetsCapSet(oldTotalAssetsCap, totalAssetsCap_);
  }

  /// @notice This function is used to deposit the first amount of assets into the vault
  /// @dev This is equivalent to deposit(firstDepositAmount_, address(this)); with _msgSender() replaced by fundingAccount_
  function _firstDeposit(address fundingAccount_, uint256 firstDepositAmount_) private {
    address receiver = address(this);
    uint256 maxAssets = maxDeposit(receiver);
    if (firstDepositAmount_ > maxAssets) revert ERC4626ExceededMaxDeposit(receiver, firstDepositAmount_, maxAssets);

    uint256 shares = previewDeposit(firstDepositAmount_);
    _deposit(fundingAccount_, receiver, firstDepositAmount_, shares);
  }

  /// @notice Returns true if the vault is paused
  function _isPaused() private view returns (bool) {
    return paused() || auth().paused();
  }

  // ERC20 OVERRIDES
  /// @notice Returns the number of decimals for the vault token
  function decimals() public view virtual override(ERC20Upgradeable, ERC4626Upgradeable, IERC20Metadata) returns (uint8) {
    return super.decimals();
  }

  // ERC4626 OVERRIDES
  /// @notice Deposits assets into the vault
  /// @dev Prevents deposits that would result in 0 shares received
  function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
    // slither-disable-next-line incorrect-equality
    if (assets > 0 && shares == 0) revert NullAmount();
    super._deposit(caller, receiver, assets, shares);
  }

  /// @notice Withdraws assets from the vault
  /// @dev Prevents withdrawals that would result in 0 assets taken
  function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal virtual override {
    // slither-disable-next-line incorrect-equality
    if (shares > 0 && assets == 0) revert NullAmount();
    super._withdraw(caller, receiver, owner, assets, shares);
  }

  /// @notice Internal function called during token transfers
  /// @dev This function is overridden to ensure that the vault is not paused
  function _update(address from, address to, uint256 value) internal virtual override notPaused {
    super._update(from, to, value);
  }

  /// @notice Returns the maximum amount that can be deposited
  function maxDeposit(address receiver) public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256) {
    return _isPaused() ? 0 : totalAssetsCap() == type(uint256).max ? super.maxDeposit(receiver) : _maxDeposit();
  }

  /// @notice Returns the maximum amount that can be minted
  function maxMint(address receiver) public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256) {
    return _isPaused() ? 0 : totalAssetsCap() == type(uint256).max ? super.maxMint(receiver) : convertToShares(_maxDeposit());
  }

  /// @notice Returns the maximum amount that can be withdrawn
  function maxWithdraw(address owner) public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256) {
    return _isPaused() ? 0 : super.maxWithdraw(owner);
  }

  /// @notice Returns the maximum amount that can be redeemed
  function maxRedeem(address owner) public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256) {
    return _isPaused() ? 0 : super.maxRedeem(owner);
  }

  /// @notice Returns the maximum amount that can be deposited
  function _maxDeposit() private view returns (uint256) {
    return Math.saturatingSub(totalAssetsCap(), totalAssets());
  }

  // VIEW FUNCTIONS
  /// @notice Returns the auth contract
  function auth() public view override returns (Auth) {
    return _getBaseVaultStorage()._auth;
  }

  /// @notice Returns the total assets cap
  function totalAssetsCap() public view override returns (uint256) {
    return _getBaseVaultStorage()._totalAssetsCap;
  }
}
