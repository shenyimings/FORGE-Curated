// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { LibDiamond } from "../../common/EIP2535/libraries/LibDiamond.sol";
import { LibRouter } from "../libraries/LibRouter.sol";

contract RouterManagementFacet {
  using EnumerableSet for EnumerableSet.AddressSet;

  /*************************
   * Public View Functions *
   *************************/

  /// @notice Return the token approve spender for the given target.
  function getSpender(address target) external view returns (address _spender) {
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    _spender = $.spenders[target];
    if (_spender == address(0)) _spender = target;
  }

  /// @notice Return the list of approved targets.
  function getApprovedTargets() external view returns (address[] memory _accounts) {
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    uint256 _numAccount = $.approvedTargets.length();
    _accounts = new address[](_numAccount);
    for (uint256 i = 0; i < _numAccount; i++) {
      _accounts[i] = $.approvedTargets.at(i);
    }
  }

  /// @notice Return the whitelist kind for the given target.
  function getWhitelisted() external view returns (address[] memory _accounts) {
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    uint256 _numAccount = $.whitelisted.length();
    _accounts = new address[](_numAccount);
    for (uint256 i = 0; i < _numAccount; i++) {
      _accounts[i] = $.whitelisted.at(i);
    }
  }

  function getRevenuePool() external view returns (address) {
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    return $.revenuePool;
  }

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Approve contract to be used in token converting.
  function approveTarget(address target, address spender) external {
    LibDiamond.enforceIsContractOwner();
    LibRouter.approveTarget(target, spender);
  }

  /// @notice Remove approve contract in token converting.
  function removeTarget(address target) external {
    LibDiamond.enforceIsContractOwner();
    LibRouter.removeTarget(target);
  }

  /// @notice Update whitelist status of the given contract.
  function updateWhitelist(address target, bool status) external {
    LibDiamond.enforceIsContractOwner();
    LibRouter.updateWhitelist(target, status);
  }

  /// @notice Update revenue pool.
  function updateRevenuePool(address revenuePool) external {
    LibDiamond.enforceIsContractOwner();
    LibRouter.updateRevenuePool(revenuePool);
  }
}
