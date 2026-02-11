// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IStrategy } from "../fund/IStrategy.sol";

import { PermissionedSwap } from "../common/utils/PermissionedSwap.sol";

contract StrategyHarvester is PermissionedSwap {
  using SafeERC20 for IERC20;

  /***********************
   * Immutable Variables *
   ***********************/

  /// @notice The address of strategy contract.
  address public immutable strategy;

  /// @notice The address of rewards receiver.
  address public immutable receiver;

  /***************
   * Constructor *
   ***************/

  constructor(address _strategy, address _receiver) initializer {
    __Context_init();
    __ERC165_init();
    __AccessControl_init();

    strategy = _strategy;
    receiver = _receiver;

    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @notice Harvest pending rewards from strategy.
  function harvest() external onlyRole(PERMISSIONED_TRADER_ROLE) {
    IStrategy(strategy).harvest(address(this));
  }

  /// @notice Harvest base token to target token by amm trading and distribute to fxSAVE.
  /// @param amountIn The amount of input tokens.
  /// @param baseToken The address of base token to use.
  /// @param targetToken The address target token.
  /// @param params The parameters used for trading.
  /// @return amountOut The amount of target token received.
  function swapAndDistribute(
    uint256 amountIn,
    address baseToken,
    address targetToken,
    TradingParameter memory params
  ) external returns (uint256 amountOut) {
    // swap base token to target
    amountOut = _doTrade(baseToken, targetToken, amountIn, params);

    // transfer target token to receiver
    IERC20(targetToken).safeTransfer(receiver, amountOut);
  }
}
