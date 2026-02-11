// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { ICurvePoolOracle } from "../interfaces/Curve/ICurvePoolOracle.sol";

import { SpotPriceOracleBase } from "./SpotPriceOracleBase.sol";
import { LSDPriceOracleBase } from "./LSDPriceOracleBase.sol";

contract StETHPriceOracle is LSDPriceOracleBase {
  /***********************
   * Immutable Variables *
   ***********************/

  /// @notice The address of curve ETH/stETH pool.
  address public immutable Curve_ETH_stETH_Pool;

  /***************
   * Constructor *
   ***************/

  constructor(
    address _spotPriceOracle,
    bytes32 _Chainlink_ETH_USD_Spot,
    address _Curve_ETH_stETH_Pool
  ) SpotPriceOracleBase(_spotPriceOracle) LSDPriceOracleBase(_Chainlink_ETH_USD_Spot) {
    Curve_ETH_stETH_Pool = _Curve_ETH_stETH_Pool;
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @inheritdoc LSDPriceOracleBase
  /// @dev [Curve stETH/ETH ema price] * [Chainlink ETH/USD spot]
  function _getLSDUSDAnchorPrice() internal view virtual override returns (uint256) {
    uint256 stETH_ETH_CurveEma = ICurvePoolOracle(Curve_ETH_stETH_Pool).price_oracle();
    uint256 ETH_USD_ChainlinkSpot = _readSpotPriceByChainlink(Chainlink_ETH_USD_Spot);
    unchecked {
      return (stETH_ETH_CurveEma * ETH_USD_ChainlinkSpot) / PRECISION;
    }
  }
}
