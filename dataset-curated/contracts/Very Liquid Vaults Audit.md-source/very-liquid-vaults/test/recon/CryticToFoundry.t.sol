// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

import "forge-std/console2.sol";

import {IVault} from "@src//IVault.sol";
import {BaseVault} from "@src/utils/BaseVault.sol";
import {TargetFunctions} from "@test/recon/TargetFunctions.t.sol";
import {Test} from "forge-std/Test.sol";

// forge test --match-contract CryticToFoundry -vv
contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
  function setUp() public {
    setup();
  }

  // forge test --match-test test_crytic -vvv
  function test_CryticToFoundry_01() public {
    sizeMetaVault_addStrategy(cryticSizeMetaVault);
    try this.sizeMetaVault_removeStrategy(cashStrategyVault, cryticSizeMetaVault, 0, 12_309_285_055_488_365_505_482_212_365_492_300_592_776_939_712_510_733_309_382_679_362_574_362_184_841) {
      assertTrue(false, "should revert");
    } catch (bytes memory err) {
      assertEq(err, abi.encodeWithSelector(BaseVault.NullAmount.selector));
    }
  }

  function test_CryticToFoundry_02() public {
    cashStrategyVault_setTotalAssetsCap(0);
    cashStrategyVault_deposit(0, 0xA0a075bA2bB014bf8F08bf91DEd27002bd87B9eE);
  }

  function test_CryticToFoundry_03() public {
    sizeMetaVault_removeStrategy(cashStrategyVault, aaveStrategyVault, 1, 0);
    erc4626_mustNotRevert_convertToShares(2_864_474_371_869_477_837_766_289_424_800_920_762_713_068_510_290_572_746_720_344_906_210_731_950_275);
  }

  function test_CryticToFoundry_04() public {
    sizeMetaVault_removeStrategy(
      erc4626StrategyVault,
      cashStrategyVault,
      12_365_772_636_688_392_640_122_225_467_814_873_084_244_657_338_905_471_971_496_106_064_405_562_446_679,
      61_713_837_595_357_171_402_281_262_959_146_600_068_603_794_227_103_927_492_545_261_743_669_128
    );
    sizeMetaVault_removeStrategy(cashStrategyVault, aaveStrategyVault, 312, 0);
    aaveStrategyVault_setTotalAssetsCap(25_150_558_811_799_922_860_235_757_451_418_943_390_228_657_999_138_837_874_545_548_576_258_909_183_598);
    erc4626_mustNotRevert_maxMint(0x51e35255066cb44807Ca732b5550A53fd73b0A1c);
  }
}
