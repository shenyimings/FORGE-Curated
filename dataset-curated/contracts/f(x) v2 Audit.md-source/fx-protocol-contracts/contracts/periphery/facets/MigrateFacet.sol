// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { IMultiPathConverter } from "../../helpers/interfaces/IMultiPathConverter.sol";
import { IBalancerVault } from "../../interfaces/Balancer/IBalancerVault.sol";
import { IPool } from "../../interfaces/IPool.sol";
import { IPoolManager } from "../../interfaces/IPoolManager.sol";
import { IFxMarketV2 } from "../../v2/interfaces/IFxMarketV2.sol";
import { IFxUSD } from "../../v2/interfaces/IFxUSD.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { LibRouter } from "../libraries/LibRouter.sol";
import { FlashLoanFacetBase } from "./FlashLoanFacetBase.sol";

contract MigrateFacet is FlashLoanFacetBase {
  using SafeERC20 for IERC20;
  using WordCodec for bytes32;

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

  /// @dev The address of USDC token.
  address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  /// @dev The address of fxUSD token.
  address private constant fxUSD = 0x085780639CC2cACd35E474e71f4d000e2405d8f6;

  /// @dev The address of wstETH market contract.
  address private constant wstETHMarket = 0xAD9A0E7C08bc9F747dF97a3E7E7f620632CB6155;

  /// @dev The address of wstETH token.
  address private constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

  /// @dev The address of fstETH token.
  address private constant fstETH = 0xD6B8162e2fb9F3EFf09bb8598ca0C8958E33A23D;

  /// @dev The address of xstETH token.
  address private constant xstETH = 0x5a097b014C547718e79030a077A91Ae37679EfF5;

  /// @dev The address of sfrxETH market contract.
  address private constant sfrxETHMarket = 0x714B853b3bA73E439c652CfE79660F329E6ebB42;

  /// @dev The address of sfrxETH token.
  address private constant sfrxETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;

  /// @dev The address of ffrxETH token.
  address private constant ffrxETH = 0xa87F04c9743Fd1933F82bdDec9692e9D97673769;

  /// @dev The address of xfrxETH token.
  address private constant xfrxETH = 0x2bb0C32101456F5960d4e994Bac183Fe0dc6C82c;

  /***********************
   * Immutable Variables *
   ***********************/

  /// @dev The address of `PoolManager` contract.
  address private immutable poolManager;

  /// @dev The address of `MultiPathConverter` contract.
  address private immutable converter;

  /***************
   * Constructor *
   ***************/

  constructor(address _balancer, address _poolManager, address _converter) FlashLoanFacetBase(_balancer) {
    poolManager = _poolManager;
    converter = _converter;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Migrate xstETH to fx position.
  /// @param pool The address of fx position pool.
  /// @param positionId The index of position.
  /// @param xTokenAmount The amount of xstETH to migrate.
  /// @param borrowAmount The amount of USDC to borrow.
  /// @param data The calldata passing to `onMigrateXstETHPosition` hook function.
  function migrateXstETHPosition(
    address pool,
    uint256 positionId,
    uint256 xTokenAmount,
    uint256 borrowAmount,
    bytes calldata data
  ) external nonReentrant {
    IERC20(xstETH).safeTransferFrom(msg.sender, address(this), xTokenAmount);
    if (positionId > 0) {
      IERC721(pool).transferFrom(msg.sender, address(this), positionId);
    }

    _invokeFlashLoan(
      USDC,
      borrowAmount,
      abi.encodeCall(
        MigrateFacet.onMigrateXstETHPosition,
        (pool, positionId, xTokenAmount, borrowAmount, msg.sender, data)
      )
    );

    // refund USDC to caller
    LibRouter.refundERC20(USDC, LibRouter.routerStorage().revenuePool);
  }

  /// @notice Migrate xfrxETH to fx position.
  /// @param pool The address of fx position pool.
  /// @param positionId The index of position.
  /// @param xTokenAmount The amount of xfrxETH to migrate.
  /// @param borrowAmount The amount of USDC to borrow.
  /// @param data The calldata passing to `onMigrateXfrxETHPosition` hook function.
  function migrateXfrxETHPosition(
    address pool,
    uint256 positionId,
    uint256 xTokenAmount,
    uint256 borrowAmount,
    bytes calldata data
  ) external nonReentrant {
    IERC20(xfrxETH).safeTransferFrom(msg.sender, address(this), xTokenAmount);
    if (positionId > 0) {
      IERC721(pool).transferFrom(msg.sender, address(this), positionId);
    }

    _invokeFlashLoan(
      USDC,
      borrowAmount,
      abi.encodeCall(
        MigrateFacet.onMigrateXfrxETHPosition,
        (pool, positionId, xTokenAmount, borrowAmount, msg.sender, data)
      )
    );

    // refund USDC to caller
    LibRouter.refundERC20(USDC, LibRouter.routerStorage().revenuePool);
  }

  /// @notice Hook for `migrateXstETHPosition`.
  /// @param pool The address of fx position pool.
  /// @param positionId The index of position.
  /// @param xTokenAmount The amount of xstETH to migrate.
  /// @param borrowAmount The amount of USDC to borrow.
  /// @param recipient The address of position holder.
  /// @param data Hook data.
  function onMigrateXstETHPosition(
    address pool,
    uint256 positionId,
    uint256 xTokenAmount,
    uint256 borrowAmount,
    address recipient,
    bytes memory data
  ) external onlySelf {
    uint256 fTokenAmount = (xTokenAmount * IERC20(fstETH).totalSupply()) / IERC20(xstETH).totalSupply();

    // swap USDC to fxUSD
    fTokenAmount = _swapUSDCToFxUSD(borrowAmount, fTokenAmount, data);

    // unwrap fxUSD as fToken
    IFxUSD(fxUSD).unwrap(wstETH, fTokenAmount, address(this));

    uint256 wstETHAmount;
    {
      wstETHAmount = IFxMarketV2(wstETHMarket).redeemXToken(xTokenAmount, address(this), 0);
      (uint256 baseOut, uint256 bonus) = IFxMarketV2(wstETHMarket).redeemFToken(fTokenAmount, address(this), 0);
      wstETHAmount += baseOut + bonus;
    }

    // since we need to swap back to USDC, mint 0.1% more fxUSD to cover slippage.
    fTokenAmount = (fTokenAmount * 1001) / 1000;

    LibRouter.approve(wstETH, poolManager, wstETHAmount);
    positionId = IPoolManager(poolManager).operate(pool, positionId, int256(wstETHAmount), int256(fTokenAmount));
    _checkPositionDebtRatio(pool, positionId, abi.decode(data, (bytes32)));
    IERC721(pool).transferFrom(address(this), recipient, positionId);

    // swap fxUSD to USDC and pay debts
    _swapFxUSDToUSDC(IERC20(fxUSD).balanceOf(address(this)), borrowAmount, data);
  }

  /// @notice Hook for `migrateXfrxETHPosition`.
  /// @param pool The address of fx position pool.
  /// @param positionId The index of position.
  /// @param xTokenAmount The amount of xstETH to migrate.
  /// @param borrowAmount The amount of USDC to borrow.
  /// @param recipient The address of position holder.
  /// @param data Hook data.
  function onMigrateXfrxETHPosition(
    address pool,
    uint256 positionId,
    uint256 xTokenAmount,
    uint256 borrowAmount,
    address recipient,
    bytes memory data
  ) external onlySelf {
    uint256 fTokenAmount = (xTokenAmount * IERC20(ffrxETH).totalSupply()) / IERC20(xfrxETH).totalSupply();

    // swap USDC to fxUSD
    fTokenAmount = _swapUSDCToFxUSD(borrowAmount, fTokenAmount, data);

    // unwrap fxUSD as fToken
    IFxUSD(fxUSD).unwrap(sfrxETH, fTokenAmount, address(this));

    uint256 wstETHAmount;
    {
      // redeem
      wstETHAmount = IFxMarketV2(sfrxETHMarket).redeemXToken(xTokenAmount, address(this), 0);
      (uint256 baseOut, uint256 bonus) = IFxMarketV2(sfrxETHMarket).redeemFToken(fTokenAmount, address(this), 0);
      wstETHAmount += baseOut + bonus;
      // swap sfrxETH to wstETH
      wstETHAmount = _swapSfrxETHToWstETH(wstETHAmount, 0, data);
    }

    // since we need to swap back to USDC, mint 0.1% more fxUSD to cover slippage.
    fTokenAmount = (fTokenAmount * 1001) / 1000;

    LibRouter.approve(wstETH, poolManager, wstETHAmount);
    positionId = IPoolManager(poolManager).operate(pool, positionId, int256(wstETHAmount), int256(fTokenAmount));
    _checkPositionDebtRatio(pool, positionId, abi.decode(data, (bytes32)));
    IERC721(pool).transferFrom(address(this), recipient, positionId);

    // swap fxUSD to USDC and pay debts
    _swapFxUSDToUSDC(IERC20(fxUSD).balanceOf(address(this)), borrowAmount, data);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to swap USDC to fxUSD.
  /// @param amountUSDC The amount of USDC to use.
  /// @param minFxUSD The minimum amount of fxUSD should receive.
  /// @param data The swap route encoding.
  /// @return amountFxUSD The amount of fxUSD received.
  function _swapUSDCToFxUSD(
    uint256 amountUSDC,
    uint256 minFxUSD,
    bytes memory data
  ) internal returns (uint256 amountFxUSD) {
    (, uint256 swapEncoding, uint256[] memory swapRoutes) = abi.decode(data, (bytes32, uint256, uint256[]));
    return _swap(USDC, amountUSDC, minFxUSD, swapEncoding, swapRoutes);
  }

  /// @dev Internal function to swap fxUSD to USDC.
  /// @param amountFxUSD The amount of fxUSD to use.
  /// @param minUSDC The minimum amount of USDC should receive.
  /// @param data The swap route encoding.
  /// @return amountUSDC The amount of USDC received.
  function _swapFxUSDToUSDC(
    uint256 amountFxUSD,
    uint256 minUSDC,
    bytes memory data
  ) internal returns (uint256 amountUSDC) {
    (, , , uint256 swapEncoding, uint256[] memory swapRoutes) = abi.decode(
      data,
      (bytes32, uint256, uint256[], uint256, uint256[])
    );
    return _swap(fxUSD, amountFxUSD, minUSDC, swapEncoding, swapRoutes);
  }

  /// @dev Internal function to swap sfrxETH to wstETH.
  /// @param amountSfrxETH The amount of sfrxETH to use.
  /// @param minWstETH The minimum amount of wstETH should receive.
  /// @param data The swap route encoding.
  /// @return amountWstETH The amount of wstETH received.
  function _swapSfrxETHToWstETH(
    uint256 amountSfrxETH,
    uint256 minWstETH,
    bytes memory data
  ) internal returns (uint256 amountWstETH) {
    (, , , , , uint256 swapEncoding, uint256[] memory swapRoutes) = abi.decode(
      data,
      (bytes32, uint256, uint256[], uint256, uint256[], uint256, uint256[])
    );
    return _swap(sfrxETH, amountSfrxETH, minWstETH, swapEncoding, swapRoutes);
  }

  /// @dev Internal function to do swap.
  /// @param token The address of input token.
  /// @param amountIn The amount of input token.
  /// @param minOut The minimum amount of output tokens should receive.
  /// @param encoding The encoding for swap routes.
  /// @param routes The swap routes to `MultiPathConverter`.
  /// @return amountOut The amount of output tokens received.
  function _swap(
    address token,
    uint256 amountIn,
    uint256 minOut,
    uint256 encoding,
    uint256[] memory routes
  ) internal returns (uint256 amountOut) {
    LibRouter.approve(token, converter, amountIn);
    amountOut = IMultiPathConverter(converter).convert(token, amountIn, encoding, routes);
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
