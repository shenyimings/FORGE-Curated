// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CryticERC4626PropertyTests} from "@crytic/properties/contracts/ERC4626/ERC4626PropertyTests.sol";
import {Setup} from "@test/Setup.t.sol";

contract AaveStrategyVaultCryticERC4626Harness is CryticERC4626PropertyTests, Setup {
  constructor() {
    deploy(address(this));
    initialize(address(cryticAaveStrategyVault), address(asset), true);
  }
}
