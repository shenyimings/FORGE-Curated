// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/token/ERC20/IERC20.sol';

import { IMitosisVault } from '../IMitosisVault.sol';
import { IStrategyExecutor } from './IStrategyExecutor.sol';
import { ITally } from './tally/ITally.sol';

interface IMatrixStrategyExecutor is IStrategyExecutor {
  error IMatrixStrategyExecutor__TallyTotalBalanceNotZero(address implementation);
  error IMatrixStrategyExecutor__TallyAlreadySet(address implementation);
  error IMatrixStrategyExecutor__StrategistNotSet();
  error IMatrixStrategyExecutor__ExecutorNotSet();
  error IMatrixStrategyExecutor__TallyNotSet(address implementation);

  function vault() external view returns (IMitosisVault);
  function asset() external view returns (IERC20);
  function hubMatrixVault() external view returns (address);

  function strategist() external view returns (address);
  function executor() external view returns (address);
  function tally() external view returns (ITally);
  function totalBalance() external view returns (uint256);
  function storedTotalBalance() external view returns (uint256);

  function deallocateLiquidity(uint256 amount) external;
  function fetchLiquidity(uint256 amount) external;
  function returnLiquidity(uint256 amount) external;
  function settle() external;
  function settleExtraRewards(address reward, uint256 amount) external;

  function setTally(address implementation) external;
  function setStrategist(address strategist_) external;
  function setExecutor(address executor_) external;
  function unsetStrategist() external;
  function unsetExecutor() external;
}
