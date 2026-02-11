// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMorphoFlashLoanCallback } from "../../interfaces/Morpho/IMorphoFlashLoanCallback.sol";

import { LibRouter } from "../libraries/LibRouter.sol";

contract MorphoFlashLoanCallbackFacet is IMorphoFlashLoanCallback {
  using SafeERC20 for IERC20;

  /**********
   * Errors *
   **********/

  /// @dev Thrown when the caller is not morpho.
  error ErrorNotFromMorpho();

  error ErrorNotFromRouterFlashLoan();

  /***********************
   * Immutable Variables *
   ***********************/

  /// @dev The address of Morpho Blue contract.
  /// In ethereum, it is 0xbbbbbbbbbb9cc5e90e3b3af64bdaf62c37eeffcb.
  address private immutable morpho;

  /***************
   * Constructor *
   ***************/

  constructor(address _morpho) {
    morpho = _morpho;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc IMorphoFlashLoanCallback
  function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
    if (msg.sender != morpho) revert ErrorNotFromMorpho();

    // make sure call invoked by router
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    if ($.flashLoanContext != LibRouter.HAS_FLASH_LOAN) revert ErrorNotFromRouterFlashLoan();

    (address token, bytes memory realData) = abi.decode(data, (address, bytes));
    (bool success, ) = address(this).call(realData);
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

    // flashloan fee is zero in Morpho
    LibRouter.approve(token, msg.sender, assets);
  }
}
