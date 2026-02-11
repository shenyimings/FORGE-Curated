// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Auth} from "@src/Auth.sol";
import {BaseVault} from "@src/utils/BaseVault.sol";
import {NonReentrantVault} from "@src/utils/NonReentrantVault.sol";

/// @title ERC4626StrategyVault
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice A strategy that invests assets in an external ERC4626-compliant vault
/// @dev Wraps an external ERC4626 vault to provide strategy functionality for the Size Meta Vault
contract ERC4626StrategyVault is NonReentrantVault {
  using SafeERC20 for IERC20;

  // STORAGE
  /// @custom:storage-location erc7201:size.storage.ERC4626StrategyVault
  struct ERC4626StrategyVaultStorage {
    IERC4626 _vault;
  }

  // keccak256(abi.encode(uint256(keccak256("size.storage.ERC4626StrategyVault")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant ERC4626StrategyVaultStorageLocation = 0x38a1b2a83634e21b8a768b344dddb96ad68dbc29f8128301f8422f40aee65000;

  function _getERC4626StrategyVaultStorage() private pure returns (ERC4626StrategyVaultStorage storage $) {
    assembly {
      $.slot := ERC4626StrategyVaultStorageLocation
    }
  }

  // EVENTS
  event VaultSet(address indexed vault);

  // INITIALIZER
  /// @notice Initializes the ERC4626StrategyVault with an external vault
  /// @dev Sets the external vault and calls parent initialization
  function initialize(Auth auth_, string memory name_, string memory symbol_, address fundingAccount, uint256 firstDepositAmount, IERC4626 vault_) public virtual initializer {
    if (address(vault_) == address(0)) revert NullAddress();

    ERC4626StrategyVaultStorage storage $ = _getERC4626StrategyVaultStorage();
    $._vault = vault_;
    emit VaultSet(address(vault_));

    super.initialize(auth_, IERC20(address(vault_.asset())), name_, symbol_, fundingAccount, firstDepositAmount);
  }

  // ERC4626 OVERRIDES
  /// @notice Returns the maximum amount that can be deposited
  function maxDeposit(address receiver) public view override(BaseVault) returns (uint256) {
    return Math.min(vault().maxDeposit(address(this)), super.maxDeposit(receiver));
  }

  /// @notice Returns the maximum number of shares that can be minted
  function maxMint(address receiver) public view override(BaseVault) returns (uint256) {
    uint256 maxDepositReceiver = maxDeposit(receiver);
    // slither-disable-next-line incorrect-equality
    uint256 maxDepositInShares = maxDepositReceiver == type(uint256).max ? type(uint256).max : _convertToShares(maxDepositReceiver, Math.Rounding.Floor);
    return Math.min(maxDepositInShares, super.maxMint(receiver));
  }

  /// @notice Returns the maximum amount that can be withdrawn by an owner
  function maxWithdraw(address owner) public view override(BaseVault) returns (uint256) {
    return Math.min(vault().maxWithdraw(address(this)), super.maxWithdraw(owner));
  }

  /// @notice Returns the maximum number of shares that can be redeemed
  function maxRedeem(address owner) public view override(BaseVault) returns (uint256) {
    uint256 maxWithdrawOwner = maxWithdraw(owner);
    // slither-disable-next-line incorrect-equality
    uint256 maxWithdrawInShares = maxWithdrawOwner == type(uint256).max ? type(uint256).max : _convertToShares(maxWithdrawOwner, Math.Rounding.Floor);
    return Math.min(maxWithdrawInShares, super.maxRedeem(owner));
  }

  /// @notice Returns the total assets managed by this strategy
  /// @dev Converts the external vault shares held by this contract to asset value
  /// @return The total assets under management
  function totalAssets() public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256) {
    return vault().convertToAssets(vault().balanceOf(address(this)));
  }

  /// @notice Internal deposit function that invests in the external vault
  /// @dev Calls parent deposit then invests the assets in the external vault
  function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
    super._deposit(caller, receiver, assets, shares);
    IERC20(asset()).forceApprove(address(vault()), assets);
    // slither-disable-next-line unused-return
    vault().deposit(assets, address(this));
  }

  /// @notice Internal withdraw function that redeems from the external vault
  /// @dev Withdraws from the external vault then calls parent withdraw
  function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal override {
    // slither-disable-next-line unused-return
    vault().withdraw(assets, address(this), address(this));
    super._withdraw(caller, receiver, owner, assets, shares);
  }

  // VIEW FUNCTIONS
  /// @notice Returns the external vault
  function vault() public view returns (IERC4626) {
    return _getERC4626StrategyVaultStorage()._vault;
  }
}
