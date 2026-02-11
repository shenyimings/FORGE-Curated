// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IERC20Metadata } from '@oz/token/ERC20/extensions/IERC20Metadata.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { AccessControlEnumerableUpgradeable } from '@ozu/access/extensions/AccessControlEnumerableUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IReclaimQueueCollector } from '../interfaces/hub/IReclaimQueueCollector.sol';
import { ERC7201Utils } from '../lib/ERC7201Utils.sol';
import { StdError } from '../lib/StdError.sol';
import { Versioned } from '../lib/Versioned.sol';

contract ReclaimQueueCollector is
  AccessControlEnumerableUpgradeable,
  UUPSUpgradeable,
  IReclaimQueueCollector,
  Versioned
{
  using ERC7201Utils for string;
  using SafeERC20 for IERC20Metadata;

  struct StorageV1 {
    address defaultRoute;
    mapping(address vault => address) routes;
  }

  string private constant _NAMESPACE = 'mitosis.storage.ReclaimQueueCollector.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  /// @notice keccak256('mitosis.role.ReclaimQueueCollector.assetManager')
  bytes32 public constant ASSET_MAANGER = 0xc50741a7e230f9a3a2d761e9b4b707ad08a64d4b66590b3ce39cc0855f715048;

  /// @notice keccak256('mitosis.role.ReclaimQueueCollector.routeManager')
  bytes32 public constant ROUTE_MANAGER = 0x29182813f2d482276e9acc24c0b57abf658c75d317a52995117d038084aa3b57;

  address public immutable reclaimQueue;

  constructor(address reclaimQueue_) {
    _disableInitializers();

    reclaimQueue = reclaimQueue_;
  }

  function initialize(address owner_) external initializer {
    __AccessControlEnumerable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, owner_);
    _grantRole(ASSET_MAANGER, owner_);
    _grantRole(ROUTE_MANAGER, owner_);

    _getStorageV1().defaultRoute = address(this);
  }

  function collect(address vault, address asset, uint256 collected) external override {
    require(_msgSender() == reclaimQueue, StdError.Unauthorized());

    address routeTo = _getRoute(_getStorageV1(), vault);

    IERC20Metadata(asset).safeTransferFrom(_msgSender(), routeTo, collected);

    emit Collected(vault, routeTo, asset, collected);
  }

  function withdraw(address asset, address receiver, uint256 amount) external onlyRole(ASSET_MAANGER) {
    IERC20Metadata(asset).safeTransfer(receiver, amount);

    emit Withdrawn(asset, receiver, amount);
  }

  function getRoute(address vault) external view returns (address) {
    return _getRoute(_getStorageV1(), vault);
  }

  function getDefaultRoute() external view returns (address) {
    return _getStorageV1().defaultRoute;
  }

  function setRoute(address vault, address route) external onlyRole(ROUTE_MANAGER) {
    _getStorageV1().routes[vault] = route;

    emit RouteSet(vault, route);
  }

  function setDefaultRoute(address route) external onlyRole(ROUTE_MANAGER) {
    _getStorageV1().defaultRoute = route;

    emit DefaultRouteSet(route);
  }

  function _getRoute(StorageV1 storage $, address vault) internal view returns (address) {
    address route = $.routes[vault];
    address routeTo = route == address(0) ? $.defaultRoute : route;
    return routeTo;
  }

  function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }
}
