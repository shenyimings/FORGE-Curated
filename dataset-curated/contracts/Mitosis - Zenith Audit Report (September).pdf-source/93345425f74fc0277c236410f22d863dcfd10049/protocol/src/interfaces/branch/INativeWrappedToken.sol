// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IERC20 } from '@oz/interfaces/IERC20.sol';

interface INativeWrappedToken is IERC20 {
  function deposit() external payable;

  function withdraw(uint256 amount) external;
}
