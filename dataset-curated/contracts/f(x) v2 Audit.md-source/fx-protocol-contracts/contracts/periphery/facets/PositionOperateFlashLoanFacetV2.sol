// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { IMultiPathConverter } from "../../helpers/interfaces/IMultiPathConverter.sol";
import { IPoolManager } from "../../interfaces/IPoolManager.sol";
import { IPool } from "../../interfaces/IPool.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { LibRouter } from "../libraries/LibRouter.sol";
import { MorphoFlashLoanFacetBase } from "./MorphoFlashLoanFacetBase.sol";

contract PositionOperateFlashLoanFacetV2 is MorphoFlashLoanFacetBase {
  using EnumerableSet for EnumerableSet.AddressSet;
  using SafeERC20 for IERC20;
  using WordCodec for bytes32;

  /**********
   * Events *
   **********/

  event OpenOrAdd(address pool, uint256 position, address recipient, uint256 colls, uint256 debts, uint256 borrows);

  event CloseOrRemove(address pool, uint256 position, address recipient, uint256 colls, uint256 debts, uint256 borrows);

  /**********
   * Errors *
   **********/

  /// @dev Thrown when the amount of tokens swapped are not enough.
  error ErrorInsufficientAmountSwapped();

  /// @dev Thrown when debt ratio out of range.
  error ErrorDebtRatioOutOfRange();

  /*************
   * Constants *
   *************/

  address private constant fxUSD = 0x085780639CC2cACd35E474e71f4d000e2405d8f6;

  /***********************
   * Immutable Variables *
   ***********************/

  /// @dev The address of `PoolManager` contract.
  address private immutable poolManager;

  /***************
   * Constructor *
   ***************/

  constructor(address _morpho, address _poolManager) MorphoFlashLoanFacetBase(_morpho) {
    poolManager = _poolManager;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Open a new position or add collateral to position with any tokens.
  /// @param params The parameters to convert source token to collateral token.
  /// @param pool The address of fx position pool.
  /// @param positionId The index of position.
  /// @param borrowAmount The amount of collateral token to borrow.
  /// @param data Hook data passing to `onOpenOrAddPositionFlashLoan`.
  function openOrAddPositionFlashLoanV2(
    LibRouter.ConvertInParams memory params,
    address pool,
    uint256 positionId,
    uint256 borrowAmount,
    bytes calldata data
  ) external payable nonReentrant {
    uint256 amountIn = LibRouter.transferInAndConvert(params, IPool(pool).collateralToken()) + borrowAmount;
    _invokeFlashLoan(
      IPool(pool).collateralToken(),
      borrowAmount,
      abi.encodeCall(
        PositionOperateFlashLoanFacetV2.onOpenOrAddPositionFlashLoanV2,
        (pool, positionId, amountIn, borrowAmount, msg.sender, data)
      )
    );
    // transfer extra collateral token to revenue pool
    LibRouter.refundERC20(IPool(pool).collateralToken(), LibRouter.routerStorage().revenuePool);
  }

  /// @notice Close a position or remove collateral from position.
  /// @param params The parameters to convert collateral token to target token.
  /// @param positionId The index of position.
  /// @param pool The address of fx position pool.
  /// @param borrowAmount The amount of collateral token to borrow.
  /// @param data Hook data passing to `onCloseOrRemovePositionFlashLoan`.
  function closeOrRemovePositionFlashLoanV2(
    LibRouter.ConvertOutParams memory params,
    address pool,
    uint256 positionId,
    uint256 amountOut,
    uint256 borrowAmount,
    bytes calldata data
  ) external nonReentrant {
    address collateralToken = IPool(pool).collateralToken();

    _invokeFlashLoan(
      collateralToken,
      borrowAmount,
      abi.encodeCall(
        PositionOperateFlashLoanFacetV2.onCloseOrRemovePositionFlashLoanV2,
        (pool, positionId, amountOut, borrowAmount, msg.sender, data)
      )
    );

    // convert collateral token to other token
    amountOut = IERC20(collateralToken).balanceOf(address(this));
    LibRouter.convertAndTransferOut(params, collateralToken, amountOut, msg.sender);

    // transfer extra fxUSD to revenue pool
    LibRouter.refundERC20(fxUSD, LibRouter.routerStorage().revenuePool);
  }

  /// @notice Hook for `openOrAddPositionFlashLoan`.
  /// @param pool The address of fx position pool.
  /// @param position The index of position.
  /// @param amount The amount of collateral token to supply.
  /// @param repayAmount The amount of collateral token to repay.
  /// @param recipient The address of position holder.
  /// @param data Hook data passing to `onOpenOrAddPositionFlashLoan`.
  function onOpenOrAddPositionFlashLoanV2(
    address pool,
    uint256 position,
    uint256 amount,
    uint256 repayAmount,
    address recipient,
    bytes memory data
  ) external onlySelf {
    (bytes32 miscData, uint256 fxUSDAmount, address swapTarget, bytes memory swapData) = abi.decode(
      data,
      (bytes32, uint256, address, bytes)
    );

    // open or add collateral to position
    if (position != 0) {
      IERC721(pool).transferFrom(recipient, address(this), position);
    }
    LibRouter.approve(IPool(pool).collateralToken(), poolManager, amount);
    position = IPoolManager(poolManager).operate(pool, position, int256(amount), int256(fxUSDAmount));
    _checkPositionDebtRatio(pool, position, miscData);
    IERC721(pool).transferFrom(address(this), recipient, position);

    emit OpenOrAdd(pool, position, recipient, amount, fxUSDAmount, repayAmount);

    // swap fxUSD to collateral token
    _swap(fxUSD, IPool(pool).collateralToken(), fxUSDAmount, repayAmount, swapTarget, swapData);
  }

  /// @notice Hook for `closeOrRemovePositionFlashLoan`.
  /// @param pool The address of fx position pool.
  /// @param position The index of position.
  /// @param amount The amount of collateral token to withdraw.
  /// @param borrowAmount The amount of collateral token borrowed.
  /// @param recipient The address of position holder.
  /// @param data Hook data passing to `onCloseOrRemovePositionFlashLoan`.
  function onCloseOrRemovePositionFlashLoanV2(
    address pool,
    uint256 position,
    uint256 amount,
    uint256 borrowAmount,
    address recipient,
    bytes memory data
  ) external onlySelf {
    (bytes32 miscData, uint256 fxUSDAmount, address swapTarget, bytes memory swapData) = abi.decode(
      data,
      (bytes32, uint256, address, bytes)
    );

    // swap collateral token to fxUSD
    _swap(IPool(pool).collateralToken(), fxUSD, borrowAmount, fxUSDAmount, swapTarget, swapData);

    // close or remove collateral from position
    IERC721(pool).transferFrom(recipient, address(this), position);
    (, uint256 maxFxUSD) = IPool(pool).getPosition(position);
    if (fxUSDAmount >= maxFxUSD) {
      // close entire position
      IPoolManager(poolManager).operate(pool, position, type(int256).min, type(int256).min);
    } else {
      IPoolManager(poolManager).operate(pool, position, -int256(amount), -int256(fxUSDAmount));
      _checkPositionDebtRatio(pool, position, miscData);
    }
    IERC721(pool).transferFrom(address(this), recipient, position);

    emit CloseOrRemove(pool, position, recipient, amount, fxUSDAmount, borrowAmount);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to do swap.
  /// @param tokenIn The address of input token.
  /// @param tokenOut The address of output token.
  /// @param amountIn The amount of input token.
  /// @param minOut The minimum amount of output tokens should receive.
  /// @param swapTarget The address of target contract used for swap.
  /// @param swapData The calldata passed to target contract.
  /// @return amountOut The amount of output tokens received.
  function _swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minOut,
    address swapTarget,
    bytes memory swapData
  ) internal returns (uint256 amountOut) {
    if (amountIn == 0) return 0;

    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    if (!$.approvedTargets.contains(swapTarget)) {
      revert LibRouter.ErrorTargetNotApproved();
    }
    address spender = $.spenders[swapTarget];
    if (spender == address(0)) spender = swapTarget;
    LibRouter.approve(tokenIn, spender, amountIn);

    amountOut = IERC20(tokenOut).balanceOf(address(this));
    (bool success, ) = swapTarget.call(swapData);
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
    amountOut = IERC20(tokenOut).balanceOf(address(this)) - amountOut;

    if (amountOut < minOut) revert ErrorInsufficientAmountSwapped();
  }

  /// @dev Internal function to check debt ratio for the position.
  /// @param pool The address of fx position pool.
  /// @param positionId The index of the position.
  /// @param miscData The encoded data for debt ratio range.
  function _checkPositionDebtRatio(address pool, uint256 positionId, bytes32 miscData) internal view {
    uint256 debtRatio = IPool(pool).getPositionDebtRatio(positionId);
    uint256 minDebtRatio = miscData.decodeUint(0, 60);
    uint256 maxDebtRatio = miscData.decodeUint(60, 60);
    if (debtRatio < minDebtRatio || debtRatio > maxDebtRatio) {
      revert ErrorDebtRatioOutOfRange();
    }
  }
}
