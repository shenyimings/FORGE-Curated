// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CryticIERC4626Internal} from "@crytic/properties/contracts/ERC4626/util/IERC4626Internal.sol";

import {hevm as vm} from "@crytic/properties/contracts/util/Hevm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AaveStrategyVault} from "@src/strategies/AaveStrategyVault.sol";

import {IERC20MintBurn} from "@test/mocks/IERC20MintBurn.t.sol";
import {PoolMock} from "@test/mocks/PoolMock.t.sol";

contract CryticAaveStrategyVaultMock is AaveStrategyVault, CryticIERC4626Internal {
  function recognizeProfit(uint256 profit) external override {
    address owner = Ownable(asset()).owner();
    vm.prank(owner);
    IERC20MintBurn(asset()).mint(address(aToken()), profit);
    uint256 balance = aToken().balanceOf(asset());
    vm.prank(owner);
    PoolMock(address(pool())).setLiquidityIndex(asset(), (balance + profit) * 1e27 / balance);
  }

  function recognizeLoss(uint256 loss) external override {
    address owner = Ownable(asset()).owner();
    vm.prank(owner);
    IERC20MintBurn(asset()).burn(address(aToken()), loss);
  }
}
