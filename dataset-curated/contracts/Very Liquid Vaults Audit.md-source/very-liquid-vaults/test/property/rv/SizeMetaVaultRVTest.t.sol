// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC4626Test} from "@rv/ercx/src/ERC4626/Light/ERC4626Test.sol";
import {Setup} from "@test/Setup.t.sol";

contract SizeMetaVaultRVTest is ERC4626Test, Setup {
  function setUp() public {
    deploy(address(this));
    ERC4626Test.init(address(sizeMetaVault));
    _setupRandomSizeMetaVaultConfiguration(address(this), _getRandomUint);
  }

  function _getRandomUint(uint256 min, uint256 max) internal returns (uint256) {
    return vm.randomUint(min, max);
  }
}
