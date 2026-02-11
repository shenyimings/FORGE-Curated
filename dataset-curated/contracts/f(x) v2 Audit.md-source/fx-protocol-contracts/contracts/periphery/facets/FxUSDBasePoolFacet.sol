// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IFxUSDBasePool } from "../../interfaces/IFxUSDBasePool.sol";
import { IFxShareableRebalancePool } from "../../v2/interfaces/IFxShareableRebalancePool.sol";
import { IFxUSD } from "../../v2/interfaces/IFxUSD.sol";
import { ILiquidityGauge } from "../../voting-escrow/interfaces/ILiquidityGauge.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { LibRouter } from "../libraries/LibRouter.sol";

contract FxUSDBasePoolFacet {
  using SafeERC20 for IERC20;

  /*************
   * Constants *
   *************/

  /// @notice The address of USDC token.
  address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  /// @notice The address of fxUSD token.
  address private constant fxUSD = 0x085780639CC2cACd35E474e71f4d000e2405d8f6;

  /***********************
   * Immutable Variables *
   ***********************/

  /// @dev The address of `PoolManager` contract.
  address private immutable poolManager;

  /// @dev The address of `FxUSDBasePool` contract.
  address private immutable fxBASE;

  /// @dev The address of fxBASE gauge contract.
  address private immutable gauge;

  /***************
   * Constructor *
   ***************/

  constructor(address _poolManager, address _fxBASE, address _gauge) {
    poolManager = _poolManager;
    fxBASE = _fxBASE;
    gauge = _gauge;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Migrate fxUSD from rebalance pool to fxBASE.
  /// @param pool The address of rebalance pool.
  /// @param amountIn The amount of rebalance pool shares to migrate.
  /// @param minShares The minimum shares should receive.
  /// @param receiver The address of fxBASE share recipient.
  function migrateToFxBase(address pool, uint256 amountIn, uint256 minShares, address receiver) external {
    IFxShareableRebalancePool(pool).withdrawFrom(msg.sender, amountIn, address(this));
    address baseToken = IFxShareableRebalancePool(pool).baseToken();
    address asset = IFxShareableRebalancePool(pool).asset();
    LibRouter.approve(asset, fxUSD, amountIn);
    IFxUSD(fxUSD).wrap(baseToken, amountIn, address(this));
    LibRouter.approve(fxUSD, fxBASE, amountIn);
    IFxUSDBasePool(fxBASE).deposit(receiver, fxUSD, amountIn, minShares);
  }

  /// @notice Migrate fxUSD from rebalance pool to fxBASE gauge.
  /// @param pool The address of rebalance pool.
  /// @param amountIn The amount of rebalance pool shares to migrate.
  /// @param minShares The minimum shares should receive.
  /// @param receiver The address of fxBASE share recipient.
  function migrateToFxBaseGauge(address pool, uint256 amountIn, uint256 minShares, address receiver) external {
    IFxShareableRebalancePool(pool).withdrawFrom(msg.sender, amountIn, address(this));
    address baseToken = IFxShareableRebalancePool(pool).baseToken();
    address asset = IFxShareableRebalancePool(pool).asset();
    LibRouter.approve(asset, fxUSD, amountIn);
    IFxUSD(fxUSD).wrap(baseToken, amountIn, address(this));
    LibRouter.approve(fxUSD, fxBASE, amountIn);
    uint256 shares = IFxUSDBasePool(fxBASE).deposit(address(this), fxUSD, amountIn, minShares);
    LibRouter.approve(fxBASE, gauge, shares);
    ILiquidityGauge(gauge).deposit(shares, receiver);
  }

  /// @notice Deposit token to fxBASE.
  /// @param params The parameters to convert source token to `tokenOut`.
  /// @param tokenOut The target token, USDC or fxUSD.
  /// @param minShares The minimum shares should receive.
  /// @param receiver The address of fxBASE share recipient.
  function depositToFxBase(
    LibRouter.ConvertInParams memory params,
    address tokenOut,
    uint256 minShares,
    address receiver
  ) external payable {
    uint256 amountIn = LibRouter.transferInAndConvert(params, tokenOut);
    LibRouter.approve(tokenOut, fxBASE, amountIn);
    IFxUSDBasePool(fxBASE).deposit(receiver, tokenOut, amountIn, minShares);
  }

  /// @notice Deposit token to fxBase and then deposit to gauge.
  /// @param params The parameters to convert source token to `tokenOut`.
  /// @param tokenOut The target token, USDC or fxUSD.
  /// @param minShares The minimum shares should receive.
  /// @param receiver The address of gauge share recipient.
  function depositToFxBaseGauge(
    LibRouter.ConvertInParams memory params,
    address tokenOut,
    uint256 minShares,
    address receiver
  ) external payable {
    uint256 amountIn = LibRouter.transferInAndConvert(params, tokenOut);
    LibRouter.approve(tokenOut, fxBASE, amountIn);
    uint256 shares = IFxUSDBasePool(fxBASE).deposit(address(this), tokenOut, amountIn, minShares);
    LibRouter.approve(fxBASE, gauge, shares);
    ILiquidityGauge(gauge).deposit(shares, receiver);
  }
  
  /*
  /// @notice Burn fxBASE shares and then convert USDC and fxUSD to another token.
  /// @param fxusdParams The parameters to convert fxUSD to target token.
  /// @param usdcParams The parameters to convert USDC to target token.
  /// @param amountIn The amount of fxBASE to redeem.
  /// @param receiver The address of token recipient.
  function redeemFromFxBase(
    LibRouter.ConvertOutParams memory fxusdParams,
    LibRouter.ConvertOutParams memory usdcParams,
    uint256 amountIn,
    address receiver
  ) external {
    IERC20(fxBASE).safeTransferFrom(msg.sender, address(this), amountIn);
    (uint256 amountFxUSD, uint256 amountUSDC) = IFxUSDBasePool(fxBASE).redeem(address(this), amountIn);
    LibRouter.convertAndTransferOut(fxusdParams, fxUSD, amountFxUSD, receiver);
    LibRouter.convertAndTransferOut(usdcParams, USDC, amountUSDC, receiver);
  }

  /// @notice Burn fxBASE shares from gauge and then convert USDC and fxUSD to another token.
  /// @param fxusdParams The parameters to convert fxUSD to target token.
  /// @param usdcParams The parameters to convert USDC to target token.
  /// @param amountIn The amount of fxBASE to redeem.
  /// @param receiver The address of token recipient.
  function redeemFromFxBaseGauge(
    LibRouter.ConvertOutParams memory fxusdParams,
    LibRouter.ConvertOutParams memory usdcParams,
    uint256 amountIn,
    address receiver
  ) external {
    IERC20(gauge).safeTransferFrom(msg.sender, address(this), amountIn);
    ILiquidityGauge(gauge).withdraw(amountIn);
    (uint256 amountFxUSD, uint256 amountUSDC) = IFxUSDBasePool(fxBASE).redeem(address(this), amountIn);
    LibRouter.convertAndTransferOut(fxusdParams, fxUSD, amountFxUSD, receiver);
    LibRouter.convertAndTransferOut(usdcParams, USDC, amountUSDC, receiver);
  }
  */
}
