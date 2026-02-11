// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IMultiPathConverter } from "../../helpers/interfaces/IMultiPathConverter.sol";
import { IWrappedEther } from "../../interfaces/IWrappedEther.sol";

library LibRouter {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  /**********
   * Errors *
   **********/

  /// @dev Thrown when use unapproved target contract.
  error ErrorTargetNotApproved();

  /// @dev Thrown when msg.value is different from amount.
  error ErrorMsgValueMismatch();

  /// @dev Thrown when the output token is not enough.
  error ErrorInsufficientOutput();

  /// @dev Thrown when the whitelisted account type is incorrect.
  error ErrorNotWhitelisted();

  /*************
   * Constants *
   *************/

  /// @dev The storage slot for router storage.
  bytes32 private constant ROUTER_STORAGE_SLOT = keccak256("diamond.router.storage");

  /// @dev The address of WETH token.
  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  uint8 internal constant NOT_FLASH_LOAN = 0;

  uint8 internal constant HAS_FLASH_LOAN = 1;

  uint8 internal constant NOT_ENTRANT = 0;

  uint8 internal constant HAS_ENTRANT = 1;

  /***********
   * Structs *
   ***********/

  /// @param spenders Mapping from target address to token spender address.
  /// @param approvedTargets The list of approved target contracts.
  /// @param whitelisted The list of whitelisted contracts.
  struct RouterStorage {
    mapping(address => address) spenders;
    EnumerableSet.AddressSet approvedTargets;
    EnumerableSet.AddressSet whitelisted;
    address revenuePool;
    uint8 flashLoanContext;
    uint8 reentrantContext;
  }

  /// @notice The struct for input token convert parameters.
  ///
  /// @param tokenIn The address of source token.
  /// @param amount The amount of source token.
  /// @param target The address of converter contract.
  /// @param data The calldata passing to the target contract.
  /// @param minOut The minimum amount of output token should receive.
  /// @param signature The optional data for future usage.
  struct ConvertInParams {
    address tokenIn;
    uint256 amount;
    address target;
    bytes data;
    uint256 minOut;
    bytes signature;
  }

  /// @notice The struct for output token convert parameters.
  /// @param tokenOut The address of output token.
  /// @param converter The address of converter contract.
  /// @param encodings The encodings for `MultiPathConverter`.
  /// @param minOut The minimum amount of output token should receive.
  /// @param routes The convert route encodings.
  /// @param signature The optional data for future usage.
  struct ConvertOutParams {
    address tokenOut;
    address converter;
    uint256 encodings;
    uint256[] routes;
    uint256 minOut;
    bytes signature;
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Return the RouterStorage reference.
  function routerStorage() internal pure returns (RouterStorage storage gs) {
    bytes32 position = ROUTER_STORAGE_SLOT;
    assembly {
      gs.slot := position
    }
  }

  /// @dev Approve contract to be used in token converting.
  function approveTarget(address target, address spender) internal {
    RouterStorage storage $ = routerStorage();

    if ($.approvedTargets.add(target) && target != spender) {
      $.spenders[target] = spender;
    }
  }

  /// @dev Remove approve contract in token converting.
  function removeTarget(address target) internal {
    RouterStorage storage $ = routerStorage();

    if ($.approvedTargets.remove(target)) {
      delete $.spenders[target];
    }
  }

  /// @dev Whitelist account with type.
  function updateWhitelist(address account, bool status) internal {
    RouterStorage storage $ = routerStorage();

    if (status) {
      $.whitelisted.add(account);
    } else {
      $.whitelisted.remove(account);
    }
  }

  /// @dev Check whether the account is whitelisted with specific type.
  function ensureWhitelisted(address account) internal view {
    RouterStorage storage $ = routerStorage();
    if (!$.whitelisted.contains(account)) {
      revert ErrorNotWhitelisted();
    }
  }

  function updateRevenuePool(address revenuePool) internal {
    RouterStorage storage $ = routerStorage();
    $.revenuePool = revenuePool;
  }

  /// @dev Transfer token into this contract and convert to `tokenOut`.
  /// @param params The parameters used in token converting.
  /// @param tokenOut The address of final converted token.
  /// @return amountOut The amount of token received.
  function transferInAndConvert(ConvertInParams memory params, address tokenOut) internal returns (uint256 amountOut) {
    RouterStorage storage $ = routerStorage();
    if (!$.approvedTargets.contains(params.target)) {
      revert ErrorTargetNotApproved();
    }

    transferTokenIn(params.tokenIn, address(this), params.amount);

    amountOut = IERC20(tokenOut).balanceOf(address(this));
    if (params.tokenIn == tokenOut) return amountOut;

    bool _success;
    if (params.tokenIn == address(0)) {
      (_success, ) = params.target.call{ value: params.amount }(params.data);
    } else {
      address _spender = $.spenders[params.target];
      if (_spender == address(0)) _spender = params.target;

      approve(params.tokenIn, _spender, params.amount);
      (_success, ) = params.target.call(params.data);
    }

    // below lines will propagate inner error up
    if (!_success) {
      // solhint-disable-next-line no-inline-assembly
      assembly {
        let ptr := mload(0x40)
        let size := returndatasize()
        returndatacopy(ptr, 0, size)
        revert(ptr, size)
      }
    }

    amountOut = IERC20(tokenOut).balanceOf(address(this)) - amountOut;
  }

  /// @dev Convert `tokenIn` to other token and transfer out.
  /// @param params The parameters used in token converting.
  /// @param tokenIn The address of token to convert.
  /// @param amountIn The amount of token to convert.
  /// @return amountOut The amount of token received.
  function convertAndTransferOut(
    ConvertOutParams memory params,
    address tokenIn,
    uint256 amountIn,
    address receiver
  ) internal returns (uint256 amountOut) {
    RouterStorage storage $ = routerStorage();
    if (!$.approvedTargets.contains(params.converter)) {
      revert ErrorTargetNotApproved();
    }
    if (amountIn == 0) return 0;

    amountOut = amountIn;
    if (params.routes.length > 0) {
      approve(tokenIn, params.converter, amountIn);
      amountOut = IMultiPathConverter(params.converter).convert(tokenIn, amountIn, params.encodings, params.routes);
    }
    if (amountOut < params.minOut) revert ErrorInsufficientOutput();
    if (params.tokenOut == address(0)) {
      IWrappedEther(WETH).withdraw(amountOut);
      Address.sendValue(payable(receiver), amountOut);
    } else {
      IERC20(params.tokenOut).safeTransfer(receiver, amountOut);
    }
  }

  /// @dev Internal function to transfer token to this contract.
  /// @param token The address of token to transfer.
  /// @param amount The amount of token to transfer.
  /// @return uint256 The amount of token transferred.
  function transferTokenIn(address token, address receiver, uint256 amount) internal returns (uint256) {
    if (token == address(0)) {
      if (msg.value != amount) revert ErrorMsgValueMismatch();
    } else {
      IERC20(token).safeTransferFrom(msg.sender, receiver, amount);
    }
    return amount;
  }

  /// @dev Internal function to refund extra token.
  /// @param token The address of token to refund.
  /// @param recipient The address of the token receiver.
  function refundERC20(address token, address recipient) internal {
    uint256 _balance = IERC20(token).balanceOf(address(this));
    if (_balance > 0) {
      IERC20(token).safeTransfer(recipient, _balance);
    }
  }

  /// @dev Internal function to approve token.
  function approve(address token, address spender, uint256 amount) internal {
    IERC20(token).forceApprove(spender, amount);
  }
}
