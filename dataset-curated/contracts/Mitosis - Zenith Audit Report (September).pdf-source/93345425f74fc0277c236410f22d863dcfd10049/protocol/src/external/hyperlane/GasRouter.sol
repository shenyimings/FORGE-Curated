// SPDX-License-Identifier: MIT OR Apache-2.0
// Forked from @hyperlane-xyz/core (https://github.com/hyperlane-xyz/hyperlane-monorepo)
// - rev: https://github.com/hyperlane-xyz/hyperlane-monorepo/commit/42ccee13eb99313a4a078f36938aec6dab16990c
// Modified by Mitosis Team
//
// CHANGES:
// - Use ERC7201 Namespaced Storage for storage variables.
pragma solidity >=0.6.11;

import { StandardHookMetadata } from '@hpl/hooks/libs/StandardHookMetadata.sol';

import { ERC7201Utils } from '../../lib/ERC7201Utils.sol';
import { Router } from './Router.sol';

/*@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
     @@@@@  HYPERLANE  @@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
@@@@@@@@@       @@@@@@@@*/
abstract contract GasRouter is Router {
  using ERC7201Utils for string;

  event GasSet(uint32 domain, uint96 action, uint128 gas);

  error GasRouter__GasLimitNotSet(uint32 domain, uint96 action);

  // ============ Mutable Storage ============

  struct GasRouterConfig {
    uint32 domain;
    uint96 action;
    uint128 gas;
  }

  struct GasRouterStorage {
    mapping(uint32 => mapping(uint96 => uint128)) destinationGas;
  }

  string private constant _GAS_ROUTER_STORAGE_NAMESPACE = 'hyperlane.storage.GasRouter';
  bytes32 private immutable _slot = _GAS_ROUTER_STORAGE_NAMESPACE.storageSlot();

  function _getHplGasRouterStorage() internal view returns (GasRouterStorage storage $) {
    bytes32 slot = _slot;
    assembly {
      $.slot := slot
    }
  }

  constructor(address _mailbox) Router(_mailbox) { }

  // =========================== NOTE: MODIFIERS =========================== //

  modifier onlyGasManager() {
    _authorizeConfigureGas(_msgSender());
    _;
  }

  // =========================== NOTE: VIRTUAL FUNCTIONS =========================== //

  function _authorizeConfigureGas(address) internal virtual;

  /**
   * @notice Sets the gas amount dispatched for each configured domain.
   * @param gasConfigs The array of GasRouterConfig structs
   */
  function setDestinationGas(GasRouterConfig[] calldata gasConfigs) external onlyGasManager {
    for (uint256 i = 0; i < gasConfigs.length; i += 1) {
      _setDestinationGas(gasConfigs[i].domain, gasConfigs[i].action, gasConfigs[i].gas);
    }
  }

  /**
   * @notice Sets the gas amount dispatched for each configured domain.
   * @param domain The destination domain ID
   * @param action The action to set the gas for
   * @param gas The gas limit
   */
  function setDestinationGas(uint32 domain, uint96 action, uint128 gas) external onlyGasManager {
    _setDestinationGas(domain, action, gas);
  }

  /**
   * @notice Returns the gas payment required to dispatch a message to the given domain's router.
   * @param _destinationDomain The domain of the router.
   * @param _action The action to quote the gas for
   * @return _gasPayment Payment computed by the registered InterchainGasPaymaster.
   */
  function quoteGasPayment(uint32 _destinationDomain, uint96 _action) external view virtual returns (uint256) {
    return _GasRouter_quoteDispatch(_destinationDomain, _action, '', address(hook()));
  }

  function _GasRouter_hookMetadata(uint32 _destination, uint96 _action) internal view returns (bytes memory) {
    uint256 gasLimit = _getHplGasRouterStorage().destinationGas[_destination][_action];
    // IGP does not overrides gas limit even if it is set to zero.
    // So we need to check if the gas limit is properly set.
    require(gasLimit > 0, GasRouter__GasLimitNotSet(_destination, _action));
    return StandardHookMetadata.overrideGasLimit(gasLimit);
  }

  function _setDestinationGas(uint32 domain, uint96 action, uint128 gas) internal {
    _getHplGasRouterStorage().destinationGas[domain][action] = gas;
    emit GasSet(domain, action, gas);
  }

  function _GasRouter_dispatch(
    uint32 _destination,
    uint96 _action,
    uint256 _value,
    bytes memory _messageBody,
    address _hook
  ) internal returns (bytes32) {
    return _Router_dispatch(_destination, _value, _messageBody, _GasRouter_hookMetadata(_destination, _action), _hook);
  }

  function _GasRouter_quoteDispatch(uint32 _destination, uint96 _action, bytes memory _messageBody, address _hook)
    internal
    view
    returns (uint256)
  {
    return _Router_quoteDispatch(_destination, _messageBody, _GasRouter_hookMetadata(_destination, _action), _hook);
  }
}
