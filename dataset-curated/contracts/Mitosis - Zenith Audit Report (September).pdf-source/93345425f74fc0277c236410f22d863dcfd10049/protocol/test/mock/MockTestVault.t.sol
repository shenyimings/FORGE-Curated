// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import { IERC20 } from '@oz/token/ERC20/IERC20.sol';

contract MockTestVault {
  address _token;

  constructor(address token) {
    _token = token;
  }

  function deposit(address account, uint256 value) external {
    IERC20(_token).transferFrom(account, address(this), value);
  }
}
