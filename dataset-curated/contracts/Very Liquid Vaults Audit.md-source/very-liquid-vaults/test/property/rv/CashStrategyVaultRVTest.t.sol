// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC4626Test} from "@rv/ercx/src/ERC4626/Light/ERC4626Test.sol";
import {Setup} from "@test/Setup.t.sol";

contract CashStrategyVaultRVTest is ERC4626Test, Setup {
  function setUp() public {
    deploy(address(this));
    ERC4626Test.init(address(cashStrategyVault));
  }
}
