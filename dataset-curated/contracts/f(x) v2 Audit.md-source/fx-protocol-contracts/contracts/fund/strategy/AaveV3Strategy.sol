// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAaveRewardsController } from "../../interfaces/Aave/IAaveRewardsController.sol";
import { IAaveV3Pool } from "../../interfaces/Aave/IAaveV3Pool.sol";

import { StrategyBase } from "./StrategyBase.sol";

contract AaveV3Strategy is StrategyBase {
  using SafeERC20 for IERC20;

  address public immutable POOL;

  address public immutable INCENTIVE;

  address public immutable ASSET;

  address public immutable ATOKEN;

  uint256 public principal;

  constructor(
    address _admin,
    address _operator,
    address _pool,
    address _incentive,
    address _asset,
    address _atoken
  ) StrategyBase(_admin, _operator) {
    POOL = _pool;
    INCENTIVE = _incentive;
    ASSET = _asset;
    ATOKEN = _atoken;

    IERC20(ASSET).forceApprove(POOL, type(uint256).max);
  }

  function totalSupply() public view returns (uint256) {
    return IERC20(ATOKEN).balanceOf(address(this));
  }

  function deposit(uint256 amount) external onlyOperator {
    unchecked {
      principal += amount;
    }
    IAaveV3Pool(POOL).supply(ASSET, amount, address(this), 0);
  }

  function withdraw(uint256 amount, address recipient) external onlyOperator {
    uint256 cachedPrincipal = principal;
    if (amount > cachedPrincipal) amount = cachedPrincipal;
    unchecked {
      principal = cachedPrincipal - amount;
    }
    IAaveV3Pool(POOL).withdraw(ASSET, amount, recipient);
  }

  function kill() external onlyOperator {
    if (totalSupply() > 0) {
      IAaveV3Pool(POOL).withdraw(ASSET, type(uint256).max, operator);
    }
    principal = 0;
  }

  function _harvest(address receiver) internal virtual override {
    uint256 rewards = totalSupply() - principal;

    if (rewards > 0) {
      IAaveV3Pool(POOL).withdraw(ASSET, rewards, receiver);
    }
    address[] memory assets = new address[](1);
    assets[0] = ATOKEN;
    IAaveRewardsController(INCENTIVE).claimAllRewards(assets, receiver);
  }
}
