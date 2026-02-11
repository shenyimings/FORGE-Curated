// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseVaultMock} from "@test/mocks/BaseVaultMock.t.sol";

contract BaseVaultMockMaxDeposit0 is BaseVaultMock {
  function maxDeposit(address) public pure override returns (uint256) {
    return 0;
  }
}
