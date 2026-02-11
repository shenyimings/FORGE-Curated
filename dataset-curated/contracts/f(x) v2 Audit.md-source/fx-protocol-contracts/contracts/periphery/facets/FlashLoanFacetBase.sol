// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IBalancerVault } from "../../interfaces/Balancer/IBalancerVault.sol";

import { LibRouter } from "../libraries/LibRouter.sol";

abstract contract FlashLoanFacetBase {
  /**********
   * Errors *
   **********/

  /// @dev Thrown when the caller is not self.
  error ErrorNotFromSelf();

  /// @dev Unauthorized reentrant call.
  error ReentrancyGuardReentrantCall();

  /***********************
   * Immutable Variables *
   ***********************/

  /// @dev The address of Balancer V2 Vault.
  address private immutable balancer;

  /*************
   * Modifiers *
   *************/

  modifier onlySelf() {
    if (msg.sender != address(this)) revert ErrorNotFromSelf();
    _;
  }

  modifier onFlashLoan() {
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    $.flashLoanContext = LibRouter.HAS_FLASH_LOAN;
    _;
    $.flashLoanContext = LibRouter.NOT_FLASH_LOAN;
  }

  modifier nonReentrant() {
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    if ($.reentrantContext == LibRouter.HAS_ENTRANT) {
      revert ReentrancyGuardReentrantCall();
    }
    $.reentrantContext = LibRouter.HAS_ENTRANT;
    _;
    $.reentrantContext = LibRouter.NOT_ENTRANT;
  }

  /***************
   * Constructor *
   ***************/

  constructor(address _balancer) {
    balancer = _balancer;
  }

  /**********************
   * Internal Functions *
   **********************/

  function _invokeFlashLoan(address token, uint256 amount, bytes memory data) internal onFlashLoan {
    address[] memory tokens = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    tokens[0] = token;
    amounts[0] = amount;
    IBalancerVault(balancer).flashLoan(address(this), tokens, amounts, data);
  }
}
