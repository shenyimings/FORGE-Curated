// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC4626Test, IMockERC20} from "@a16z/erc4626-tests/ERC4626.test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseTest} from "@test/BaseTest.t.sol";

import {console3} from "console3/console3.sol";
import {console} from "forge-std/Test.sol";

contract ERC4626StrategyVaultERC4626StdTest is ERC4626Test, BaseTest {
  uint256 _delta_override = 1;

  function setUp() public override(ERC4626Test, BaseTest) {
    super.setUp();

    vm.prank(admin);
    Ownable(address(erc20Asset)).transferOwnership(address(this));

    _underlying_ = address(erc20Asset);
    _vault_ = address(erc4626StrategyVault);
    _delta_ = 0;
    _vaultMayBeEmpty = true;
    _unlimitedAmount = true;
  }

  function setUpYield(ERC4626Test.Init memory init) public override {
    uint256 balance = erc20Asset.balanceOf(address(erc4626Vault));
    if (init.yield >= 0) {
      // gain
      vm.assume(init.yield < int256(uint256(type(uint128).max)));
      init.yield = bound(init.yield, 0, int256(balance / 100));
      uint256 gain = uint256(init.yield);
      IMockERC20(_underlying_).mint(address(erc4626Vault), gain);
    } else {
      // loss
      vm.assume(init.yield > type(int128).min);
      uint256 loss = uint256(-1 * init.yield);
      vm.assume(loss < balance);
      IMockERC20(_underlying_).burn(address(erc4626Vault), loss);
    }
  }

  function test_ERC4626StrategyVaultERC4626Std_test_RT_redeem_mint_01() public {
    Init memory init = Init({
      user: [0x000000000000000000000000000000000000181f, 0x0000000000000000000000000000000000002d0B, 0x0000000000000000000000000000000000003dcd, 0x00000000000000000000000000000000E055fF88],
      share: [uint256(5441), uint256(10_097), uint256(8315), uint256(7965)],
      asset: [uint256(1285), uint256(11_837), uint256(8952), uint256(4_294_967_294)],
      yield: int256(655_649_083_344_436_783_775_280_150_831_979)
    });
    test_RT_redeem_mint(init, 991);
  }

  function test_ERC4626StrategyVaultERC4626Std_test_RT_withdraw_deposit_01() public {
    Init memory init = Init({
      user: [0x00000000000000000000000000000000000030b3, 0x0000000000000000000000000000000000002367, 0x0000000000000000000000000000000000001B08, 0x0000000000000000000000000000000000002D7E],
      share: [uint256(987_910_862), uint256(587), uint256(13_632), uint256(6506)],
      asset: [
        uint256(19_744_579_944_030_316_751_180_819),
        uint256(1_157_379_602_576_340_765_330_575_612_727_389_539_782_114_060_851_143_049_831_365),
        uint256(8645),
        uint256(42_393_604_518_183_400_894_871_284_368_897_910_331_008_433_330_724_914_529_002_052_670_013_337_269_162)
      ],
      yield: int256(11_179)
    });
    uint256 assets = 957_625_571;

    setUpVault(init);
    console.log("setUpVault");
    console3.logERC4626(address(erc4626StrategyVault), mem(init.user));
    address caller = init.user[0];
    assets = bound(assets, 0, _max_withdraw(caller));
    _approve(_underlying_, caller, _vault_, type(uint256).max);
    vm.prank(caller);
    vault_withdraw(assets, caller, caller);
    console.log("withdraw");
    console3.logERC4626(address(erc4626StrategyVault), mem(init.user));
    if (!_vaultMayBeEmpty) vm.assume(IERC20(_vault_).totalSupply() > 0);
    vm.prank(caller);
    vault_deposit(assets, caller);
    console.log("deposit");
    console3.logERC4626(address(erc4626StrategyVault), mem(init.user));
  }

  function test_ERC4626StrategyVaultERC4626Std_test_RT_withdraw_deposit_02() public {
    Init memory init = Init({
      user: [0x0000000000000000000000000000000000001DE3, 0x0000000000000000000000000000000000000618, 0x0000000000000000000000000000000000000376, 0x00000000000000000000000000000000C44b11F6],
      share: [uint256(11_327), uint256(7386), uint256(5645), uint256(1545)],
      asset: [uint256(3_607_235_850), uint256(795), uint256(1_086_394_138), uint256(15_738)],
      yield: int256(11_541)
    });
    uint256 assets = 4567;

    setUpVault(init);
    console.log("setUpVault");
    console3.logERC4626(address(erc4626StrategyVault), mem(init.user));
    address caller = init.user[0];
    uint256 assetsBefore = vault_convertToAssets(IERC4626(_vault_).balanceOf(caller));
    assets = bound(assets, 0, _max_withdraw(caller));
    _approve(_underlying_, caller, _vault_, type(uint256).max);
    vm.prank(caller);
    vault_withdraw(assets, caller, caller);
    console.log("withdraw");
    console3.logERC4626(address(erc4626StrategyVault), mem(init.user));
    if (!_vaultMayBeEmpty) vm.assume(IERC20(_vault_).totalSupply() > 0);
    vm.prank(caller);
    vault_deposit(assets, caller);
    console.log("deposit");
    console3.logERC4626(address(erc4626StrategyVault), mem(init.user));
    uint256 assetsAfter = vault_convertToAssets(IERC4626(_vault_).balanceOf(caller));
    assertApproxLeAbs(assetsAfter, assetsBefore, _delta_);
  }

  function test_ERC4626StrategyVaultERC4626Std_test_RT_withdraw_mint_01() public {
    Init memory init = Init({
      user: [0x00000000000000000000000000000000000045B1, 0x00000000000000000000000000000000000004C7, 0x0000000000000000000000000000000000000dD3, 0x000000000000000000000000000000000000102C],
      share: [uint256(3_578_229_790), uint256(13_566), uint256(14_027), uint256(767)],
      asset: [uint256(9614), uint256(6709), uint256(1303), uint256(1900)],
      yield: int256(10_430)
    });
    test_RT_withdraw_mint(init, 3_247_934_751);
  }

  function test_ERC4626StrategyVaultERC4626Std_test_RT_withdraw_mint_02() public {
    Init memory init = Init({
      user: [0x0000000000000000000000000000000000001Bfb, 0x0000000000000000000000000000000000002dE3, 0x0000000000000000000000000000000000001601, 0x0000000000000000000000000000000000000378],
      share: [uint256(75_854_176_709_581_508_612_146), uint256(7918), uint256(1182), uint256(5227)],
      asset: [uint256(1769), uint256(16_625), uint256(7900), uint256(7056)],
      yield: int256(5271)
    });
    uint256 assets = 11_357;

    setUpVault(init);
    console.log("setUpVault");
    console3.logERC4626(address(erc4626StrategyVault), mem(init.user));
    address caller = init.user[0];
    uint256 assetsBefore = vault_convertToAssets(IERC4626(_vault_).balanceOf(caller)) + IERC20(_underlying_).balanceOf(caller);
    assets = bound(assets, 0, _max_withdraw(caller));
    _approve(_underlying_, caller, _vault_, type(uint256).max);
    vm.prank(caller);
    uint256 shares = vault_withdraw(assets, caller, caller);
    console.log("withdraw");
    console3.logERC4626(address(erc4626StrategyVault), mem(init.user));
    if (!_vaultMayBeEmpty) vm.assume(IERC20(_vault_).totalSupply() > 0);
    vm.prank(caller);
    vault_mint(shares, caller);
    console.log("mint");
    console3.logERC4626(address(erc4626StrategyVault), mem(init.user));
    uint256 assetsAfter = vault_convertToAssets(IERC4626(_vault_).balanceOf(caller)) + IERC20(_underlying_).balanceOf(caller);
    assertApproxLeAbs(assetsAfter, assetsBefore, _delta_);
  }

  function test_ERC4626StrategyVaultERC4626Std_test_maxMint_01() public {
    Init memory init = Init({
      user: [0x72cbcc0eCF008bd151050f8E8c91810f66526E52, 0x872d1165C78Ac0404FE3A285569de46689146476, 0x1f9072705e30109f308ba631B1e8f70b1B0CcDD7, 0x6da0BeB596b6a57f6870cDFA950D595790B43b1e],
      share: [
        uint256(896_314_097_417_655_031_046_185_652_627_229_580_028_727_320_350_350_855_862_752_385),
        uint256(118_695_560_193_917_510_522_791_774_949_605_613_513_539_074_567),
        uint256(83_016_169_650_913_169_875_730_119_951_785_497_189_622),
        uint256(20_757_945_133_893_542_125_523_546_241_623_580_816_704_730_381_761_407)
      ],
      asset: [
        uint256(1_047_670_355_713_124_868_562_994_516_364),
        uint256(241_758_116_489_151_121_949_361_130),
        uint256(958_618_297_277),
        uint256(54_297_745_647_038_787_966_504_255_723_555_531_564_748_753_303_182_781_069_211_629_934)
      ],
      yield: int256(-14)
    });
    test_maxMint(init);
  }

  function testFuzz_ERC4626StrategyVaultERC4626Std_deposit_withdraw_totalAssets_slippage(Init memory initV1, Init memory initV2, uint256 A, address V2) public {
    _delta_ = _delta_override;

    _vault_ = address(erc4626StrategyVault);
    address V1 = _vault_;
    setUpVault(initV1);
    setUpYield(initV1);
    address[3] memory vaults = [address(aaveStrategyVault), address(cashStrategyVault), address(cryticERC4626StrategyVault)];
    V2 = vaults[uint256(uint160(V2)) % vaults.length];
    _vault_ = V2;
    setUpVault(initV2);
    // setUpYield(initV2);

    _vault_ = V1;
    address caller = initV1.user[0];
    uint256 maxWithdraw = IERC4626(V1).maxWithdraw(caller);
    vm.assume(maxWithdraw >= 1);
    uint256 assets = bound(A, 1, maxWithdraw);
    uint256 totalAssetsV1Before = IERC4626(V1).totalAssets();
    uint256 totalAssetsV2Before = IERC4626(V2).totalAssets();
    vm.prank(caller);
    vault_withdraw(assets, caller, caller);

    _vault_ = V2;
    _approve(_underlying_, caller, _vault_, type(uint256).max);
    vm.prank(caller);
    vault_deposit(assets, caller);

    uint256 totalAssetsV1After = IERC4626(V1).totalAssets();
    uint256 totalAssetsV2After = IERC4626(V2).totalAssets();
    assertApproxEqAbs(totalAssetsV1After + totalAssetsV2After, totalAssetsV1Before + totalAssetsV2Before, _delta_);
  }

  function test_ERC4626StrategyVaultERC4626Std_deposit_withdraw_totalAssets_slippage_01() public {
    bytes memory data =
      hex"ac60ae8d0000000000000000000000000000000000000000000000000000000000000614000000000000000000000000000000000000000000000000000000006bd76d2500000000000000000000000000000000000000000000000000000000000030550000000000000000000000000000000000000000000000000000000000005913000000000000000000000000000000000000000000000000000000000000385c000000000000000000000000000000000000000000000000000000004c9c8ce30000000000000000000000000000000000000000000000000000000000005b8500000000000000000000000000000000000000000000000000000000000027180000000000000000000000000000000000000000000000000000000000002fd2000000000000000000000000000000000000000000000000000000000000356b000000000000000000000000000000000000000000000000000000000000558d53697a6520416176652055534420436f696e205374726174656779205661756c000000000000000000000000000000000000000000000000000000006c6f6ae100000000000000000000000000000000000000000000000000000000000022a200000000000000000000000000000000000000000000000000000000000004640000000000000000000000000000000000000000000000000000000000002e070000000000000000000000000000000000000000000000000000000000000cd300000000000000000000000000000000000000000000000000000000000043e1000000000000000000000000000000000000000000000000000000000000495d00000000000000000000000000000000000000000000000000000000000008d5000000000000000000000000000000000000000000000000000000000000188800000000000000000000000000000000000000000000000000000000426173640000000000000000000000000000000000000000000000000000000000004b6c0000000000000000000000000000000000000000000000000000000000001ca50000000000000000000000000000000000000000000000000000000000004bc4000000000000000000000000000000000000000000000000000000000000111b0000000000000000000000000000000000000000000000000000000000000bef0000000000000000000000000000000000000000000000000000000000000cf5";
    (bool success,) = address(this).call(data);
    assertTrue(success);
  }
}
