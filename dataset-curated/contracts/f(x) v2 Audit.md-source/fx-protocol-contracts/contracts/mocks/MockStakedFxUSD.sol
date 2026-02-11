// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { AggregatorV3Interface } from "../interfaces/Chainlink/AggregatorV3Interface.sol";
import { IPoolManager } from "../interfaces/IPoolManager.sol";

contract MockFxUSDSave {
  /// @notice The address of `PoolManager` contract.
  address public immutable poolManager;

  /// @notice The address of `PegKeeper` contract.
  address public immutable pegKeeper;

  /// @dev This is also the address of FxUSD token.
  address public immutable yieldToken;

  /// @dev The address of USDC token.
  address public immutable stableToken;

  uint256 private immutable stableTokenScale;

  /// @notice The Chainlink USDC/USD price feed.
  /// @dev The encoding is below.
  /// ```text
  /// |  32 bits  | 64 bits |  160 bits  |
  /// | heartbeat |  scale  | price_feed |
  /// |low                          high |
  /// ```
  bytes32 public immutable Chainlink_USDC_USD_Spot;

  constructor(
    address _poolManager,
    address _pegKeeper,
    address _yieldToken,
    address _stableToken,
    bytes32 _Chainlink_USDC_USD_Spot
  ) {
    poolManager = _poolManager;
    pegKeeper = _pegKeeper;
    yieldToken = _yieldToken;
    stableToken = _stableToken;
    Chainlink_USDC_USD_Spot = _Chainlink_USDC_USD_Spot;

    stableTokenScale = 10 ** (18 - IERC20Metadata(_stableToken).decimals());
  }

  function totalYieldToken() external view returns (uint256) {
    return IERC20Metadata(yieldToken).balanceOf(address(this));
  }

  /// @notice The total amount of stable token managed in this contract
  function totalStableToken() external view returns (uint256) {
    return IERC20Metadata(stableToken).balanceOf(address(this));
  }

  function getStableTokenPrice() public view returns (uint256) {
    bytes32 encoding = Chainlink_USDC_USD_Spot;
    address aggregator;
    uint256 scale;
    uint256 heartbeat;
    assembly {
      aggregator := shr(96, encoding)
      scale := and(shr(32, encoding), 0xffffffffffffffff)
      heartbeat := and(encoding, 0xffffffff)
    }
    (, int256 answer, , uint256 updatedAt, ) = AggregatorV3Interface(aggregator).latestRoundData();
    if (answer < 0) revert("invalid");
    if (block.timestamp - updatedAt > heartbeat) revert("expired");
    return uint256(answer) * scale;
  }

  function getStableTokenPriceWithScale() public view returns (uint256) {
    return getStableTokenPrice() * stableTokenScale;
  }

  function rebalance(
    address pool,
    int16 tickId,
    uint256 maxFxUSD,
    uint256 maxStable
  ) external returns (uint256 colls, uint256 yieldTokenUsed, uint256 stableTokenUsed) {
    IERC20Metadata(yieldToken).approve(poolManager, type(uint256).max);
    IERC20Metadata(stableToken).approve(poolManager, type(uint256).max);
    (colls, yieldTokenUsed, stableTokenUsed) = IPoolManager(poolManager).rebalance(
      pool,
      msg.sender,
      tickId,
      maxFxUSD,
      maxStable
    );
  }

  function rebalance(
    address pool,
    uint256 maxFxUSD,
    uint256 maxStable
  ) external returns (uint256 colls, uint256 yieldTokenUsed, uint256 stableTokenUsed) {
    IERC20Metadata(yieldToken).approve(poolManager, type(uint256).max);
    IERC20Metadata(stableToken).approve(poolManager, type(uint256).max);
    (colls, yieldTokenUsed, stableTokenUsed) = IPoolManager(poolManager).rebalance(
      pool,
      msg.sender,
      maxFxUSD,
      maxStable
    );
  }

  function liquidate(
    address pool,
    uint256 maxFxUSD,
    uint256 maxStable
  ) external returns (uint256 colls, uint256 yieldTokenUsed, uint256 stableTokenUsed) {
    IERC20Metadata(yieldToken).approve(poolManager, type(uint256).max);
    IERC20Metadata(stableToken).approve(poolManager, type(uint256).max);
    (colls, yieldTokenUsed, stableTokenUsed) = IPoolManager(poolManager).liquidate(
      pool,
      msg.sender,
      maxFxUSD,
      maxStable
    );
  }
}
