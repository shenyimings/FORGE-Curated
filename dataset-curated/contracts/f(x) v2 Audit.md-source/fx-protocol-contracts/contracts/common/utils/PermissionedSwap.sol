// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// solhint-disable avoid-low-level-calls
// solhint-disable no-inline-assembly

abstract contract PermissionedSwap is AccessControlUpgradeable {
  using SafeERC20 for IERC20;

  /**********
   * Errors *
   **********/

  /// @dev Thrown when the amount of output token is not enough.
  error InsufficientOutputToken();

  /*************
   * Constants *
   *************/

  /// @notice The role for permissioned trader.
  bytes32 public constant PERMISSIONED_TRADER_ROLE = keccak256("PERMISSIONED_TRADER_ROLE");

  /// @notice The role for permissioned trading router.
  bytes32 public constant PERMISSIONED_ROUTER_ROLE = keccak256("PERMISSIONED_ROUTER_ROLE");

  /***********
   * Structs *
   ***********/

  /// @notice The struct for trading parameters.
  ///
  /// @param router The address of trading router.
  /// @param data The calldata passing to the router contract.
  /// @param minOut The minimum amount of output token should receive.
  struct TradingParameter {
    address router;
    bytes data;
    uint256 minOut;
  }

  /*************
   * Variables *
   *************/

  /// @dev reserved slots.
  uint256[50] private __gap;

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Withdraw base token to someone else.
  /// @dev This should be only used when we are retiring this contract.
  /// @param baseToken The address of base token.
  function withdraw(address baseToken, address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 amountIn = IERC20(baseToken).balanceOf(address(this));
    IERC20(baseToken).safeTransfer(recipient, amountIn);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to convert token with routes.
  /// @param srcToken The address of source token.
  /// @param dstToken The address of destination token.
  /// @param amountIn The amount of input token.
  /// @param params The token converting parameters.
  /// @return amountOut The amount of output token received.
  function _doTrade(
    address srcToken,
    address dstToken,
    uint256 amountIn,
    TradingParameter memory params
  ) internal virtual onlyRole(PERMISSIONED_TRADER_ROLE) returns (uint256 amountOut) {
    if (srcToken == dstToken) return amountIn;

    // router should be permissioned
    _checkRole(PERMISSIONED_ROUTER_ROLE, params.router);

    // approve to router
    IERC20(srcToken).forceApprove(params.router, amountIn);

    // do trading
    amountOut = IERC20(dstToken).balanceOf(address(this));
    (bool success, ) = params.router.call(params.data);
    if (!success) {
      // below lines will propagate inner error up
      assembly {
        let ptr := mload(0x40)
        let size := returndatasize()
        returndatacopy(ptr, 0, size)
        revert(ptr, size)
      }
    }

    amountOut = IERC20(dstToken).balanceOf(address(this)) - amountOut;
    if (amountOut < params.minOut) {
      revert InsufficientOutputToken();
    }
  }
}
