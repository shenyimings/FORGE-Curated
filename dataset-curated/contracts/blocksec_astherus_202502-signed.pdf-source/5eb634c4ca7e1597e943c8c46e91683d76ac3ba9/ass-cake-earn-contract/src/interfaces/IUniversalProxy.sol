// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Universal Proxy Contract interface
/// @notice Using for other protocols proxy call, for example: PancakeSwap, StakeDAO and etc.
interface IUniversalProxy {
  function lock(uint256 amount) external;
  function extendLock() external;
}
