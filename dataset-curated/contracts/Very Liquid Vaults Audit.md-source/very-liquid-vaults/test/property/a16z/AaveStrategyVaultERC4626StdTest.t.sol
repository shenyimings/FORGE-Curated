// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC4626Test, IMockERC20} from "@a16z/erc4626-tests/ERC4626.test.sol";

import {WadRayMath} from "@aave/contracts/protocol/libraries/math/WadRayMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseTest} from "@test/BaseTest.t.sol";

import {console3} from "console3/console3.sol";
import {console} from "forge-std/Test.sol";

contract AaveStrategyVaultERC4626StdTest is ERC4626Test, BaseTest {
  function setUp() public override(ERC4626Test, BaseTest) {
    super.setUp();

    vm.prank(admin);
    Ownable(address(erc20Asset)).transferOwnership(address(this));

    _underlying_ = address(erc20Asset);
    _vault_ = address(aaveStrategyVault);

    // these properties can break even if we assume a more security-focused property such as "the user cannot get more assets from RT operations"
    //   since Aave rounding is inconsistent so totalAssts may round up/down at times
    //   nevertheless, the delta will be at most 2 (one for each operation)
    _delta_ = 2;
    _vaultMayBeEmpty = true;
    _unlimitedAmount = true;
  }

  function setUpYield(ERC4626Test.Init memory init) public override {
    uint256 balance = erc20Asset.balanceOf(address(aToken));
    if (init.yield >= 0) {
      // gain
      vm.assume(init.yield < int256(uint256(type(uint128).max)));
      init.yield = bound(init.yield, 0, int256(balance / 100));
      uint256 gain = uint256(init.yield);
      IMockERC20(_underlying_).mint(address(aToken), gain);
      vm.prank(admin);
      pool.setLiquidityIndex(address(erc20Asset), (balance + gain) * WadRayMath.RAY / balance);
    } else {
      // loss
      vm.assume(init.yield > type(int128).min);
      uint256 loss = uint256(-1 * init.yield);
      vm.assume(loss < balance);
      IMockERC20(_underlying_).burn(address(aToken), loss);
    }
  }

  function test_AaveStrategyVaultERC4626StdTest_RT_withdraw_mint_01() public {
    Init memory init = Init({
      user: [0x000000000000000000000000000000000000369F, 0x000000000000000000000000000000000000097B, 0x0000000000000000000000000000000000000974, 0x00000000000000000000000000000000bf92857D],
      share: [uint256(3_212_384_070), uint256(4897), uint256(579), uint256(11_295)],
      asset: [uint256(7109), uint256(6682), uint256(1168), uint256(4352)],
      yield: int256(15_660)
    });
    test_RT_withdraw_mint(init, 3_118_930_328);
  }

  function test_AaveStrategyVaultERC4626StdTest_RT_redeem_mint_01() public {
    // [FAIL; counterexample: calldata=0x840f3a740000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470c0000000000000000000000000000000000000000000000000000000000002e740000000000000000000000000000000000000000000000000000000000001e470000000000000000000000000000000000000000000000000000000000001b96000000000000000000000000000000000000000000000000000000002489f7f6000000000000000000000000000000000000000000000000000000000000141d0000000000000000000000000000000000000000000000000000000000004383000000000000000000000000000000000000000000000000000000000000478500000000000000000000000000000000000004ee2d6d415b85acef8100000000000000000000000000000000000000000000000000000000000000000000065900000000000000000000000000000000000000000000000000000000000042b50000000000000000000000000000000000000000000000000000000000003d0900000000000000000000000000000000000000000000000000000000cfc0cc330000000000000000000000000000000000000000000000000000000000002e1c args=[Init({ user: [0x2e234dAE75c793F67a35089C9D99245e1C58470c, 0x0000000000000000000000000000000000002e74, 0x0000000000000000000000000000000000001e47, 0x0000000000000000000000000000000000001B96], share: [613021686 [6.13e8], 5149, 17283 [1.728e4], 18309 [1.83e4]], asset: [100000000000000000000000000000000 [1e32], 1625, 17077 [1.707e4], 15625 [1.562e4]], yield: 3485518899 [3.485e9] }), 11804 [1.18e4]]] test_RT_redeem_mint((address[4],uint256[4],uint256[4],int256),uint256) (runs: 2304, μ: 861475, ~: 861614)
    Init memory init = Init({
      user: [0x2e234dAE75c793F67a35089C9D99245e1C58470c, 0x0000000000000000000000000000000000002e74, 0x0000000000000000000000000000000000001e47, 0x0000000000000000000000000000000000001B96],
      share: [uint256(613_021_686), uint256(5149), uint256(17_283), uint256(18_309)],
      asset: [uint256(100_000_000_000_000_000_000_000_000_000_000), uint256(1625), uint256(17_077), uint256(15_625)],
      yield: int256(3_485_518_899)
    });
    uint256 shares = 11_804;
    setUpVault(init);
    console3.logERC4626(address(aaveStrategyVault), mem(init.user));
    console.log("aToken.totalSupply", aToken.totalSupply());
    console.log("aToken.balanceOf(aaveStrategyVault)", aToken.balanceOf(address(aaveStrategyVault)));
    console.log("aToken.balanceOf(cryticAaveStrategyVault)", aToken.balanceOf(address(cryticAaveStrategyVault)));
    address caller = init.user[0];
    shares = bound(shares, 0, _max_redeem(caller));
    _approve(_underlying_, caller, _vault_, type(uint256).max);
    uint256 assetsBefore = vault_convertToAssets(IERC4626(_vault_).balanceOf(caller)) + IERC20(_underlying_).balanceOf(caller);
    vm.prank(caller);
    vault_redeem(shares, caller, caller);
    console.log("aToken.totalSupply", aToken.totalSupply());
    console.log("aToken.balanceOf(aaveStrategyVault)", aToken.balanceOf(address(aaveStrategyVault)));
    console.log("aToken.balanceOf(cryticAaveStrategyVault)", aToken.balanceOf(address(cryticAaveStrategyVault)));
    console3.logERC4626(address(aaveStrategyVault), mem(init.user));
    if (!_vaultMayBeEmpty) vm.assume(IERC20(_vault_).totalSupply() > 0);
    vm.prank(caller);
    vault_mint(shares, caller);
    uint256 assetsAfter = vault_convertToAssets(IERC4626(_vault_).balanceOf(caller)) + IERC20(_underlying_).balanceOf(caller);
    assertApproxLeAbs(assetsAfter, assetsBefore, _delta_);
    console3.logERC4626(address(aaveStrategyVault), mem(init.user));
    console.log("aToken.totalSupply", aToken.totalSupply());
    console.log("aToken.balanceOf(aaveStrategyVault)", aToken.balanceOf(address(aaveStrategyVault)));
    console.log("aToken.balanceOf(cryticAaveStrategyVault)", aToken.balanceOf(address(cryticAaveStrategyVault)));
  }

  function test_AaveStrategyVaultERC4626StdTest_RT_withdraw_mint_02() public {
    // [FAIL; counterexample: calldata=0x6aaa88bc0000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470c0000000000000000000000000000000000000000000000000000000000002e740000000000000000000000000000000000000000000000000000000000001e470000000000000000000000000000000000000000000000000000000000001b96000000000000000000000000000000000000000000000000000000002489f7f6000000000000000000000000000000000000000000000000000000000000141d0000000000000000000000000000000000000000000000000000000000004383000000000000000000000000000000000000000000000000000000000000478500000000000000000000000000000000000004ee2d6d415b85acef8100000000000000000000000000000000000000000000000000000000000000000000065900000000000000000000000000000000000000000000000000000000000042b50000000000000000000000000000000000000000000000000000000000003d0900000000000000000000000000000000000000000000000000000000cfc0cc330000000000000000000000000000000000000000000000000000000000002e1c args=[Init({ user: [0x2e234dAE75c793F67a35089C9D99245e1C58470c, 0x0000000000000000000000000000000000002e74, 0x0000000000000000000000000000000000001e47, 0x0000000000000000000000000000000000001B96], share: [613021686 [6.13e8], 5149, 17283 [1.728e4], 18309 [1.83e4]], asset: [100000000000000000000000000000000 [1e32], 1625, 17077 [1.707e4], 15625 [1.562e4]], yield: 3485518899 [3.485e9] }), 11804 [1.18e4]]] test_RT_withdraw_mint((address[4],uint256[4],uint256[4],int256),uint256) (runs: 0, μ: 0, ~: 0)
    Init memory init = Init({
      user: [0x2e234dAE75c793F67a35089C9D99245e1C58470c, 0x0000000000000000000000000000000000002e74, 0x0000000000000000000000000000000000001e47, 0x0000000000000000000000000000000000001B96],
      share: [uint256(613_021_686), uint256(5149), uint256(5149), uint256(18_309)],
      asset: [uint256(100_000_000_000_000_000_000_000_000_000_000), uint256(1625), uint256(17_077), uint256(15_625)],
      yield: int256(3_485_518_899)
    });
    test_RT_withdraw_mint(init, 11_804);
  }
}
