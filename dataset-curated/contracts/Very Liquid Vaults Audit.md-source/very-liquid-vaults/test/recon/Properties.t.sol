// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";

import {PropertiesSpecifications} from "@test/property/PropertiesSpecifications.t.sol";
import {Ghosts} from "@test/recon/Ghosts.t.sol";

abstract contract Properties is Ghosts, Asserts, PropertiesSpecifications {
  function property_SOLVENCY_01() public {
    address[] memory _actors = _getActors();
    uint256 assets = 0;
    for (uint256 i = 0; i < _actors.length; i++) {
      address _actor = _actors[i];
      uint256 balanceOf = erc20Asset.balanceOf(_actor);
      assets += sizeMetaVault.convertToAssets(balanceOf);
    }
    lte(assets, sizeMetaVault.totalAssets(), SOLVENCY_01);
  }

  function property_STRATEGY_02() public {
    gt(sizeMetaVault.strategiesCount(), 0, STRATEGY_02);
  }
}
