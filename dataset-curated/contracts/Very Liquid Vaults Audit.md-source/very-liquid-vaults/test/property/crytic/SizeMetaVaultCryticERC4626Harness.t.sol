// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CryticERC4626PropertyTests} from "@crytic/properties/contracts/ERC4626/ERC4626PropertyTests.sol";

import {hevm} from "@crytic/properties/contracts/util/Hevm.sol";
import {IVault} from "@src//IVault.sol";
import {Setup} from "@test/Setup.t.sol";

contract SizeMetaVaultCryticERC4626Harness is CryticERC4626PropertyTests, Setup {
  constructor() {
    deploy(address(this));
    initialize(address(sizeMetaVault), address(asset), true);
    _setupRandomSizeMetaVaultConfiguration(address(this), _getRandomUint2);
  }

  function rebalance(address strategyFrom, address strategyTo, uint256 amount, uint256 maxSlippagePercent) public {
    hevm.prank(address(this));
    sizeMetaVault.rebalance(IVault(strategyFrom), IVault(strategyTo), amount, maxSlippagePercent);
  }

  function _getRandomUint2(uint256 min, uint256 max) internal view returns (uint256) {
    uint256 prng = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, block.number)));
    return prng % (max - min + 1) + min;
  }
}
