// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20VotesUpgradeable} from
  "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20PermitUpgradeable} from
  "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title ZkTokenV1
/// @author [ScopeLift](https://scopelift.co)
/// @notice A proxy-upgradeable governance token with minting and burning capability gated by access controls.
/// @dev The same incrementing nonce is used in both the `delegateBySig` and `permit` function. If a client is
/// calling these functions one after the other then they should use an incremented nonce for the subsequent call.
/// @custom:security-contact security@zksync.io
contract ZkTokenV1 is Initializable, ERC20VotesUpgradeable, AccessControlUpgradeable {
  using SignatureChecker for address;

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

  /// @notice Type hash used when encoding data for `delegateOnBehalf` calls.
  bytes32 public constant DELEGATION_TYPEHASH =
    keccak256("Delegation(address owner,address delegatee,uint256 nonce,uint256 expiry)");

  /// @dev The clock was incorrectly modified.
  error ERC6372InconsistentClock();

  /// @dev Thrown if a signature for selecting a delegate expired.
  error DelegateSignatureExpired(uint256 expiry);

  /// @dev Thrown if a signature for selecting a delegate is invalid.
  error DelegateSignatureIsInvalid();

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

  /// @inheritdoc ERC20VotesUpgradeable
  /// @dev Overriding the clock to be timestamp based rather than clock based.
  function clock() public view virtual override returns (uint48) {
    return SafeCastUpgradeable.toUint48(block.timestamp);
  }

  /// @inheritdoc ERC20VotesUpgradeable
  /// @dev Overriding the clock mode to be timestamp based rather than clock based.
  function CLOCK_MODE() public view virtual override returns (string memory) {
    if (clock() != SafeCastUpgradeable.toUint48(block.timestamp)) {
      revert ERC6372InconsistentClock();
    }
    return "mode=timestamp";
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

  /// @notice Delegates votes from signer to `_delegatee` by EIP-1271/ECDSA signature.
  /// @dev This method should be used instead of `delegateBySig` as it supports validations via EIP-1271.
  /// @param _signer The address of the token holder delegating their voting power.
  /// @param _delegatee The address to which the voting power is delegated.
  /// @param _expiry The timestamp at which the signed message expires.
  /// @param _signature The signature proving the `_signer` has authorized the delegation.
  function delegateOnBehalf(address _signer, address _delegatee, uint256 _expiry, bytes memory _signature) external {
    if (block.timestamp > _expiry) {
      revert DelegateSignatureExpired(_expiry);
    }
    bool _isSignatureValid = _signer.isValidSignatureNow(
      _hashTypedDataV4(keccak256(abi.encode(DELEGATION_TYPEHASH, _signer, _delegatee, _useNonce(_signer), _expiry))),
      _signature
    );

    if (!_isSignatureValid) {
      revert DelegateSignatureIsInvalid();
    }
    _delegate(_signer, _delegatee);
  }
}
