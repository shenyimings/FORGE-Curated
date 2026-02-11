// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {BaseVault} from "@src/utils/BaseVault.sol";

/// @title NonReentrantVault
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice A vault that is non-reentrant
/// @dev Extends BaseVault to make it non-reentrant
abstract contract NonReentrantVault is BaseVault {
  // ERC4626 OVERRIDES
  function deposit(uint256 assets, address receiver) public override(ERC4626Upgradeable, IERC4626) nonReentrant emitVaultStatus returns (uint256) {
    return super.deposit(assets, receiver);
  }

  function mint(uint256 shares, address receiver) public override(ERC4626Upgradeable, IERC4626) nonReentrant emitVaultStatus returns (uint256) {
    return super.mint(shares, receiver);
  }

  function withdraw(uint256 assets, address receiver, address owner) public override(ERC4626Upgradeable, IERC4626) nonReentrant emitVaultStatus returns (uint256) {
    return super.withdraw(assets, receiver, owner);
  }

  function redeem(uint256 shares, address receiver, address owner) public override(ERC4626Upgradeable, IERC4626) nonReentrant emitVaultStatus returns (uint256) {
    return super.redeem(shares, receiver, owner);
  }
}
