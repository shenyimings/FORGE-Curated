// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IFlashLoanRecipient } from "../../interfaces/Balancer/IFlashLoanRecipient.sol";

import { LibRouter } from "../libraries/LibRouter.sol";

contract FlashLoanCallbackFacet is IFlashLoanRecipient {
  using SafeERC20 for IERC20;

  /**********
   * Errors *
   **********/

  /// @dev Thrown when the caller is not balancer vault.
  error ErrorNotFromBalancer();

  error ErrorNotFromRouterFlashLoan();

  /***********************
   * Immutable Variables *
   ***********************/

  /// @dev The address of Balancer V2 Vault.
  address private immutable balancer;

  /***************
   * Constructor *
   ***************/

  constructor(address _balancer) {
    balancer = _balancer;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc IFlashLoanRecipient
  /// @dev Balancer V2 callback
  function receiveFlashLoan(
    address[] memory tokens,
    uint256[] memory amounts,
    uint256[] memory feeAmounts,
    bytes memory userData
  ) external {
    if (msg.sender != balancer) revert ErrorNotFromBalancer();

    // make sure call invoked by router
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    if ($.flashLoanContext != LibRouter.HAS_FLASH_LOAN) revert ErrorNotFromRouterFlashLoan();

    (bool success, ) = address(this).call(userData);
    // below lines will propagate inner error up
    if (!success) {
      // solhint-disable-next-line no-inline-assembly
      assembly {
        let ptr := mload(0x40)
        let size := returndatasize()
        returndatacopy(ptr, 0, size)
        revert(ptr, size)
      }
    }

    for (uint256 i = 0; i < tokens.length; i++) {
      IERC20(tokens[i]).safeTransfer(msg.sender, amounts[i] + feeAmounts[i]);
    }
  }
}
