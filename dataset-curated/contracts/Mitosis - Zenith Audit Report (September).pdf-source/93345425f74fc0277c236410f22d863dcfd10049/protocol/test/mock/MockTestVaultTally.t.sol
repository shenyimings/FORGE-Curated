// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import { IERC20 } from '@oz/token/ERC20/IERC20.sol';

import { StdTally } from '../../src/branch/strategy/tally/StdTally.sol';

contract MockTestVaultTally is StdTally {
  address _token;
  address _testVault;

  constructor(address token, address testVault) {
    _token = token;
    _testVault = testVault;
  }

  function _totalBalance(bytes memory) internal view override returns (uint256 totalBalance_) {
    return IERC20(_token).balanceOf(_testVault);
  }
}
