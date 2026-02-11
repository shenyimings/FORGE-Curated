// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IFxUSDBasePool } from "../../interfaces/IFxUSDBasePool.sol";
import { ISavingFxUSD } from "../../interfaces/ISavingFxUSD.sol";
import { IFxShareableRebalancePool } from "../../v2/interfaces/IFxShareableRebalancePool.sol";
import { IFxUSD } from "../../v2/interfaces/IFxUSD.sol";
import { ILiquidityGauge } from "../../voting-escrow/interfaces/ILiquidityGauge.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { LibRouter } from "../libraries/LibRouter.sol";

contract SavingFxUSDFacet {
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

  /// @dev The address of `FxUSDBasePool` contract.
  address private immutable fxBASE;

  /// @dev The address of `SavingFxUSD` contract.
  address private immutable fxSAVE;

  /***************
   * Constructor *
   ***************/

  constructor(address _fxBASE, address _fxSAVE) {
    fxBASE = _fxBASE;
    fxSAVE = _fxSAVE;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Deposit token to fxSAVE.
  /// @param params The parameters to convert source token to `tokenOut`.
  /// @param tokenOut The target token, USDC or fxUSD.
  /// @param minShares The minimum shares should receive.
  /// @param receiver The address of fxSAVE share recipient.
  function depositToFxSave(
    LibRouter.ConvertInParams memory params,
    address tokenOut,
    uint256 minShares,
    address receiver
  ) external payable {
    uint256 amountIn = LibRouter.transferInAndConvert(params, tokenOut);
    LibRouter.approve(tokenOut, fxBASE, amountIn);
    uint256 shares = IFxUSDBasePool(fxBASE).deposit(address(this), tokenOut, amountIn, minShares);
    LibRouter.approve(fxBASE, fxSAVE, shares);
    IERC4626(fxSAVE).deposit(shares, receiver);
  }

  /// @notice Burn fxSave shares and then convert USDC and fxUSD to another token.
  /// @param fxusdParams The parameters to convert fxUSD to target token.
  /// @param usdcParams The parameters to convert USDC to target token.
  /// @param receiver The address of token recipient.
  function redeemFromFxSave(
    LibRouter.ConvertOutParams memory fxusdParams,
    LibRouter.ConvertOutParams memory usdcParams,
    address receiver
  ) external {
    ISavingFxUSD(fxSAVE).claimFor(msg.sender, address(this));
    uint256 amountFxUSD = IERC20(fxUSD).balanceOf(address(this));
    uint256 amountUSDC = IERC20(USDC).balanceOf(address(this));
    LibRouter.convertAndTransferOut(fxusdParams, fxUSD, amountFxUSD, receiver);
    LibRouter.convertAndTransferOut(usdcParams, USDC, amountUSDC, receiver);
  }

  /// @notice Burn fxSave shares and then convert USDC and fxUSD to another token instantly.
  /// @param fxusdParams The parameters to convert fxUSD to target token.
  /// @param usdcParams The parameters to convert USDC to target token.
  /// @param receiver The address of token recipient.
  function instantRedeemFromFxSave(
    LibRouter.ConvertOutParams memory fxusdParams,
    LibRouter.ConvertOutParams memory usdcParams,
    uint256 shares,
    address receiver
  ) external {
    uint256 assets = IERC4626(fxSAVE).redeem(shares, address(this), msg.sender);
    (uint256 amountFxUSD, uint256 amountUSDC) = IFxUSDBasePool(fxBASE).instantRedeem(address(this), assets);
    LibRouter.convertAndTransferOut(fxusdParams, fxUSD, amountFxUSD, receiver);
    LibRouter.convertAndTransferOut(usdcParams, USDC, amountUSDC, receiver);
  }
}
