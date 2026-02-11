// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IMorpho } from "../../interfaces/Morpho/IMorpho.sol";

import { LibRouter } from "../libraries/LibRouter.sol";

abstract contract MorphoFlashLoanFacetBase {
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

  /// @dev The address of Morpho Blue contract.
  /// In ethereum, it is 0xbbbbbbbbbb9cc5e90e3b3af64bdaf62c37eeffcb.
  address private immutable morpho;

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

  constructor(address _morpho) {
    morpho = _morpho;
  }

  /**********************
   * Internal Functions *
   **********************/

  function _invokeFlashLoan(address token, uint256 amount, bytes memory data) internal onFlashLoan {
    IMorpho(morpho).flashLoan(token, amount, abi.encode(token, data));
  }
}
