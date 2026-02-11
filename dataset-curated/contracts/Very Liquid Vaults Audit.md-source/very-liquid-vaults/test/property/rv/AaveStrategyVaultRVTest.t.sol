// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC4626Test} from "@rv/ercx/src/ERC4626/Light/ERC4626Test.sol";
import {Setup} from "@test/Setup.t.sol";

contract AaveStrategyVaultRVTest is ERC4626Test, Setup {
  function setUp() public {
    deploy(address(this));
    ERC4626Test.init(address(aaveStrategyVault));
  }

  // NOTE: this test fails because AToken.mint does not allow 0 amount
  function testDepositZeroAmountIsPossible() public override {
    // ignore
  }

  // NOTE: this test fails because AToken.mint does not allow 0 amount
  function testMintZeroAmountIsPossible() public override {
    // ignore
  }

  // NOTE: this test fails because AToken.burn does not allow 0 amount
  function testRedeemZeroAmountIsPossible() public override {
    // ignore
  }

  // NOTE: this test fails because AToken.burn does not allow 0 amount
  function testWithdrawZeroAmountIsPossible() public override {
    // ignore
  }

  // see https://github.com/runtimeverification/ercx-tests/issues/10
  function maxAssets() internal pure override returns (uint256) {
    return uint256(type(uint128).max);
  }

  // see https://github.com/runtimeverification/ercx-tests/issues/10
  function maxShares() internal pure override returns (uint256) {
    return uint256(type(uint128).max);
  }
}
