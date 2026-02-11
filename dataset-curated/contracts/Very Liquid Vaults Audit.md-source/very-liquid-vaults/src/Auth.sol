// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {MulticallUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/MulticallUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";

bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
bytes32 constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
bytes32 constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
bytes32 constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

/// @title Auth
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice Authority acccess control contract with global pause functionality for the Size Meta Vault system
contract Auth is UUPSUpgradeable, AccessControlEnumerableUpgradeable, PausableUpgradeable, MulticallUpgradeable {
  error NullAddress();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the Auth contract with an admin address
  /// @dev Grants all necessary roles to the admin address
  function initialize(address admin_) public initializer {
    if (admin_ == address(0)) revert NullAddress();

    __AccessControl_init();
    __AccessControlEnumerable_init();
    __Pausable_init();
    __Multicall_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    _grantRole(VAULT_MANAGER_ROLE, admin_);
    _grantRole(STRATEGIST_ROLE, admin_);
    _grantRole(GUARDIAN_ROLE, admin_);
  }

  /// @notice Authorizes contract upgrades
  /// @dev Only addresses with DEFAULT_ADMIN_ROLE can authorize upgrades
  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

  /// @notice Pauses the contract
  /// @dev Only addresses with GUARDIAN_ROLE can pause the contract
  function pause() external onlyRole(GUARDIAN_ROLE) {
    _pause();
  }

  /// @notice Unpauses the contract
  /// @dev Only addresses with VAULT_MANAGER_ROLE can unpause the contract
  function unpause() external onlyRole(VAULT_MANAGER_ROLE) {
    _unpause();
  }
}
