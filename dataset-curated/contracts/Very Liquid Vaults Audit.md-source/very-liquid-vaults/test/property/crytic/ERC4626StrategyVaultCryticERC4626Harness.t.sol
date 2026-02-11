// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CryticERC4626PropertyTests} from "@crytic/properties/contracts/ERC4626/ERC4626PropertyTests.sol";
import {Setup} from "@test/Setup.t.sol";

contract ERC4626StrategyVaultCryticERC4626Harness is CryticERC4626PropertyTests, Setup {
  constructor() {
    deploy(address(this));
    initialize(address(cryticERC4626StrategyVault), address(asset), true);
  }
}
