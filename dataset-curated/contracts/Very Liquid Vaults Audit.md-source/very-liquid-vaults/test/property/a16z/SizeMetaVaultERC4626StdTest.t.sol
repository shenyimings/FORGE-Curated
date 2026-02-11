// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC4626Test, IMockERC20} from "@a16z/erc4626-tests/ERC4626.test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BaseTest} from "@test/BaseTest.t.sol";

contract SizeMetaVaultERC4626StdTest is ERC4626Test, BaseTest {
  function setUp() public override(ERC4626Test, BaseTest) {
    super.setUp();

    vm.prank(admin);
    Ownable(address(erc20Asset)).transferOwnership(address(this));

    _underlying_ = address(erc20Asset);
    _vault_ = address(sizeMetaVault);
    _delta_ = 0;
    _vaultMayBeEmpty = true;
    _unlimitedAmount = true;

    _setupRandomSizeMetaVaultConfiguration(admin, _getRandomUint);
  }

  function setUpYield(ERC4626Test.Init memory init) public override {
    uint256 balance = erc20Asset.balanceOf(address(cashStrategyVault));
    if (init.yield >= 0) {
      // gain
      vm.assume(init.yield < int256(uint256(type(uint128).max)));
      init.yield = bound(init.yield, 0, int256(balance / 100));
      uint256 gain = uint256(init.yield);
      IMockERC20(_underlying_).mint(address(cashStrategyVault), gain);
    } else {
      // loss
      vm.assume(init.yield > type(int128).min);
      uint256 loss = uint256(-1 * init.yield);
      vm.assume(loss < balance);
      IMockERC20(_underlying_).burn(address(cashStrategyVault), loss);
    }
  }
}
