// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { TransferLimiter } from "./TransferLimiter.sol";

/**
  * @title AsBnbOFTAdapter Contract
  * @dev AsBnbOFTAdapter is a contract that adapts the ERC20 token to the OFT functionality.
    Users can transfer their token by lock their tokens into this contract,
    and receive the 1:1 backed token on the other chain.
  */
contract AsBnbOFTAdapter is
  OFTAdapterUpgradeable,
  TransferLimiter,
  AccessControlUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable
{
  // pause role
  bytes32 public constant PAUSER = keccak256("PAUSER");
  // manager role
  bytes32 public constant MANAGER = keccak256("MANAGER");

  constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {
    _disableInitializers();
  }

  /**
   * @dev Initializes the AsBnbOFTAdapter
   * @param _admin The address of the admin.
   * @param _manager The address of the manager.
   * @param _pauser The address of the pauser.
   * @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
   */
  function initialize(
    address _admin,
    address _manager,
    address _pauser,
    address _delegate
  ) external initializer {
    __OFTAdapter_init(_delegate);
    __Ownable_init(_admin);
    __AccessControl_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);
    _grantRole(PAUSER, _pauser);
  }

  /**
   * @dev Credits user with the token if the contract is not paused.
   * @param _to The address of the user to be credited.
   * @param _amountLD The amount of tokens to be transferred.
   * @return amountReceivedLD The actual amount of tokens received.
   */
  function _credit(
    address _to,
    uint256 _amountLD,
    uint32 _srcEid
  ) internal virtual override whenNotPaused returns (uint256 amountReceivedLD) {
    return super._credit(_to, _amountLD, _srcEid);
  }

  /**
   * @dev Checks and updates the rate limit before initiating a token transfer.
   * @param _amountLD The amount of tokens to be transferred.
   * @param _minAmountLD The minimum amount of tokens expected to be received.
   * @param _dstEid The destination endpoint identifier.
   * @return amountSentLD The actual amount of tokens sent.
   * @return amountReceivedLD The actual amount of tokens received.
   */
  function _debit(
    address _from,
    uint256 _amountLD,
    uint256 _minAmountLD,
    uint32 _dstEid
  ) internal virtual override whenNotPaused returns (uint256 amountSentLD, uint256 amountReceivedLD) {
    // remove dust before checking
    uint256 _amount = _removeDust(_amountLD);
    _checkAndUpdateTransferLimit(_dstEid, _amount, _from);
    return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
  }

  /* ============================
          Admin Functions
  ============================ */
  /**
   * @dev Flips the pause state
   */
  function unpause() external onlyRole(MANAGER) {
    _unpause();
  }

  /**
   * @dev pause the contract
   */
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  /**
   * @dev Sets the transfer limit configurations based on TransferLimit array. Only callable by the owner or the rate limiter.
   * @param _transferLimitConfigs An array of TransferLimit structures defining the transfer limits.
   */
  function setTransferLimitConfigs(TransferLimit[] calldata _transferLimitConfigs) external onlyRole(MANAGER) {
    _setTransferLimitConfigs(_transferLimitConfigs);
  }

  /* ============================
         Internal Functions
  ============================ */
  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
