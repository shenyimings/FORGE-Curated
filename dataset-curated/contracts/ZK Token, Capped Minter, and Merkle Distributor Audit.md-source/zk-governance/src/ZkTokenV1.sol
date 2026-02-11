// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20VotesUpgradeable} from
  "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20PermitUpgradeable} from
  "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";

/// @title ZkTokenV1
/// @author [ScopeLift](https://scopelift.co)
/// @notice A proxy-upgradeable governance token with minting and burning capability gated by access controls.
contract ZkTokenV1 is Initializable, ERC20VotesUpgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable {
  /// @notice The unique identifier constant used to represent the administrator of the minter role. An address that
  /// has this role may grant or revoke the minter role from other addresses. This role itself may be granted or
  /// revoked by the DEFAULT_ADMIN_ROLE.
  bytes32 public constant MINTER_ADMIN_ROLE = keccak256("MINTER_ADMIN_ROLE");

  /// @notice The unique identifier constant used to represent the administrator of the burner role. An address that
  /// has this role may grant or revoke the burner role from other addresses. This role itself may be granted or
  /// revoked by the DEFAULT_ADMIN_ROLE.
  bytes32 public constant BURNER_ADMIN_ROLE = keccak256("BURNER_ADMIN_ROLE");

  /// @notice The unique identifier constant used to represent the minter role. An address that has this role may call
  /// the `mint` method, creating new tokens and assigning them to specified address. This role may be granted or
  /// revoked by the MINTER_ADMIN_ROLE.
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  /// @notice The unique identifier constant used to represent the burner role. An address that has this role may call
  /// the `burn` method, destroying tokens held by a given address, removing them from the total supply. This role may
  // be granted or revoked by and address holding the BURNER_ADMIN_ROLE.
  bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

  /// @notice A one-time configuration method meant to be called immediately upon the deployment of ZkTokenV1. It sets
  /// up the token's name and symbol, configures and assigns role admins, and mints the initial token supply.
  /// @param _admin The address that will be be assigned all three role admins
  /// @param _mintReceiver The address that will receive the initial token supply.
  /// @param _mintAmount The amount of tokens, in raw decimals, that will be minted to the mint receiver's wallet.
  function initialize(address _admin, address _mintReceiver, uint256 _mintAmount) external initializer {
    __ERC20_init("zkSync", "ZK");
    __ERC20Permit_init("zkSync");
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MINTER_ADMIN_ROLE, _admin);
    _grantRole(BURNER_ADMIN_ROLE, _admin);
    _setRoleAdmin(MINTER_ROLE, MINTER_ADMIN_ROLE);
    _setRoleAdmin(BURNER_ROLE, BURNER_ADMIN_ROLE);
    _mint(_mintReceiver, _mintAmount);
  }

  /// @notice Creates a new quantity of tokens for a given address.
  /// @param _to The address that will receive the new tokens.
  /// @param _amount The quantity of tokens, in raw decimals, that will be created.
  /// @dev This method may only be called by an address that has been assigned the minter role by the minter role
  /// admin.
  function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE) {
    _mint(_to, _amount);
  }

  /// @notice Destroys tokens held by a given address and removes them from the total supply.
  /// @param _from The address from which tokens will be removed and destroyed.
  /// @param _amount The quantity of tokens, in raw decimals, that will be destroyed.
  /// @dev This method may only be called by an address that has been assigned the burner role by the burner role
  /// admin.
  function burn(address _from, uint256 _amount) external onlyRole(BURNER_ROLE) {
    _burn(_from, _amount);
  }

  /// @inheritdoc ERC20PermitUpgradeable
  /// @dev Overriding this function to resolve ambiguity in the inheritance hierarchy.
  function nonces(address owner) public view override(ERC20PermitUpgradeable, NoncesUpgradeable) returns (uint256) {
    return ERC20PermitUpgradeable.nonces(owner);
  }

  /// @inheritdoc ERC20VotesUpgradeable
  /// @dev Overriding this function to resolve ambiguity in the inheritance hierarchy.
  function _update(address from, address to, uint256 value) internal override(ERC20VotesUpgradeable, ERC20Upgradeable) {
    ERC20VotesUpgradeable._update(from, to, value);
  }
}
