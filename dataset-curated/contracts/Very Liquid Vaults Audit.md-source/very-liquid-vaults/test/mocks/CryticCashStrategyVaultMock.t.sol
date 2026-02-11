// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CryticIERC4626Internal} from "@crytic/properties/contracts/ERC4626/util/IERC4626Internal.sol";

import {hevm as vm} from "@crytic/properties/contracts/util/Hevm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CashStrategyVault} from "@src/strategies/CashStrategyVault.sol";

import {IERC20MintBurn} from "@test/mocks/IERC20MintBurn.t.sol";

contract CryticCashStrategyVaultMock is CashStrategyVault, CryticIERC4626Internal {
  function recognizeProfit(uint256 profit) external override {
    address owner = Ownable(asset()).owner();
    vm.prank(owner);
    IERC20MintBurn(asset()).mint(address(this), profit);
  }

  function recognizeLoss(uint256 loss) external override {
    address owner = Ownable(asset()).owner();
    vm.prank(owner);
    IERC20MintBurn(asset()).burn(address(this), loss);
  }
}
