// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/token/ERC20/IERC20.sol';

import { IMitosisVault } from '../IMitosisVault.sol';
import { IStrategyExecutor } from './IStrategyExecutor.sol';
import { ITally } from './tally/ITally.sol';

interface IVLFStrategyExecutor is IStrategyExecutor {
  error IVLFStrategyExecutor__TallyTotalBalanceNotZero(address implementation);
  error IVLFStrategyExecutor__TallyAlreadySet(address implementation);
  error IVLFStrategyExecutor__StrategistNotSet();
  error IVLFStrategyExecutor__ExecutorNotSet();

  function vault() external view returns (IMitosisVault);
  function asset() external view returns (IERC20);
  function hubVLFVault() external view returns (address);

  function strategist() external view returns (address);
  function executor() external view returns (address);
  function tally() external view returns (ITally);
  function totalBalance() external view returns (uint256);
  function storedTotalBalance() external view returns (uint256);

  function quoteDeallocateLiquidity(uint256 amount) external view returns (uint256);
  function quoteSettleYield(uint256 amount) external view returns (uint256);
  function quoteSettleLoss(uint256 amount) external view returns (uint256);
  function quoteSettleExtraRewards(address reward, uint256 amount) external view returns (uint256);

  function deallocateLiquidity(uint256 amount) external payable;
  function fetchLiquidity(uint256 amount) external;
  function returnLiquidity(uint256 amount) external;
  function settle() external payable;
  function settleExtraRewards(address reward, uint256 amount) external payable;

  function setTally(address implementation) external;
  function setStrategist(address strategist_) external;
  function setExecutor(address executor_) external;
  function unsetStrategist() external;
  function unsetExecutor() external;
}
