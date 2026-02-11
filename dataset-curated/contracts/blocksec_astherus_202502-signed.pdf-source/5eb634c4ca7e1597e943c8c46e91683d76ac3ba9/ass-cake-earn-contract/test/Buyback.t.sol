// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Buyback } from "../src/Buyback.sol";
import { MockERC20 } from "../src/mock/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IBuyback.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract BuybackTest is Test {
  using Address for address payable;
  Buyback public buyback;
  address public manager = makeAddr("MANAGER");
  address public admin = makeAddr("ADMIN");
  address public pauser = makeAddr("PAUSER");
  address public bot = makeAddr("BOT");

  address public receiver = 0xf4903f4544558515b26ec4C6D6e91D2293b27275;
  address public oneInchRouter = 0x111111125421cA6dc452d289314280a0f8842A65;
  address public swapDstToken = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

  address public swapSrcToken = 0xbA2aE424d960c26247Dd6c32edC70B295c744C43;
  address public swapNativeSrcToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  address public user1 = address(0xACC4);

  // get swapData from api.1inch.dev
  /**
curl --location 'https://api.1inch.dev/swap/v6.0/56/swap?src=0xba2ae424d960c26247dd6c32edc70b295c744c43&dst=0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82&amount=1000000000000000000&from=0xA1b3A6E32fB27e98D1299ab8Cd5602CBc1B00077&slippage=1&receiver=0xf4903f4544558515b26ec4C6D6e91D2293b27275&disableEstimate=true&chain=56' \
--header 'Authorization: {Authorization}' \
*/
  bytes public swapData =
    hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000ba2ae424d960c26247dd6c32edc70b295c744c430000000000000000000000000e09fabb73bd3ade0a17ecc321fd13a19e81ce82000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000f4903f4544558515b26ec4c6d6e91d2293b272750000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000003d4bf4f81bfc6fdf0e820000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000009f40000000000000000000000000000000000000000000009d60009a800095e00a0c9e75c480000000000000000090100000000000000000000000000000000000000000000000000093000038500a007e5c0d200000000000000000000000000000000000000000000000000036100021a00a0c9e75c4800000000000013130a020000000000000000000000000000000000000001ec0001710000f600007b0c20ba2ae424d960c26247dd6c32edc70b295c744c43dcbc1d9d48016b8d5f3b0f9045eb3b72f38e6b936ae4071118000f4240dcbc1d9d48016b8d5f3b0f9045eb3b72f38e6b93000000000000000000000000000000000000000000000071db751811626c27a0ba2ae424d960c26247dd6c32edc70b295c744c430c20ba2ae424d960c26247dd6c32edc70b295c744c435784425c93f264ef667a0695317196a3bb457c556ae4071118001e84805784425c93f264ef667a0695317196a3bb457c5500000000000000000000000000000000000000000000020e8f00f92461bf41a0ba2ae424d960c26247dd6c32edc70b295c744c430c20ba2ae424d960c26247dd6c32edc70b295c744c430fa119e6a12e3540c2412f9eda0221ffd16a79346ae4071118002625a00fa119e6a12e3540c2412f9eda0221ffd16a79340000000000000000000000000000000000000000000003a903d7fad689998e2cba2ae424d960c26247dd6c32edc70b295c744c430c20ba2ae424d960c26247dd6c32edc70b295c744c43f8e9b725e0de8a9546916861c2904b0eb8805b966ae4071118002dc6c0f8e9b725e0de8a9546916861c2904b0eb8805b960000000000000000000000000000000000000000000003bd1a9ef967e1a2f0d2ba2ae424d960c26247dd6c32edc70b295c744c4300a0c9e75c48000000000000002e02020000000000000000000000000000000000000000000001190000ca00007b0c2055d398326f99059ff775485246999027b3197955a39af17ce4a8eb807e076805da1e2b8ea7d0755b6ae4071118002625a0a39af17ce4a8eb807e076805da1e2b8ea7d0755b00000000000000000000000000000000000000000000003654894dfbbe84180755d398326f99059ff775485246999027b319795502a000000000000000000000000000000000000000000000003661c39f5a6ed3d02bee63c1e500e04d921d6ab7c3ef2eee14dd7a95be5706a1ea9355d398326f99059ff775485246999027b319795502a00000000000000000000000000000000000000000000004e1c50420c9348a46d4ee63c1e5007f51c8aaa6b0599abd16674e2b17fec7a9f674a155d398326f99059ff775485246999027b319795500a007e5c0d20000000000000000000000000000000000000000000000000005870003c500a0c9e75c480000000028050201010100000000000000000000000000039700031c0002a10002260001ab00007b0c20ba2ae424d960c26247dd6c32edc70b295c744c43b3432500334e8b08f12a66916912456aad1c78c96ae40711d8002dc6c0b3432500334e8b08f12a66916912456aad1c78c9000000000000000000000000000000000000000000000000242eeece25de3021ba2ae424d960c26247dd6c32edc70b295c744c435106c9a0f685f39d05d835c369036251ee3aeaaf3c47ba2ae424d960c26247dd6c32edc70b295c744c43000438ed173900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b37e4663029637a00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000000000000000000000000000000000000067108a930000000000000000000000000000000000000000000000000000000000000002000000000000000000000000ba2ae424d960c26247dd6c32edc70b295c744c43000000000000000000000000bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c0c20ba2ae424d960c26247dd6c32edc70b295c744c43b8b20a1e5595bfeb21df0e162be2744a7ed325816ae4071198001e8480b8b20a1e5595bfeb21df0e162be2744a7ed3258100000000000000000000000000000000000000000000000054cb0a379017fc79ba2ae424d960c26247dd6c32edc70b295c744c430c20ba2ae424d960c26247dd6c32edc70b295c744c43fd1ef328a17a8e8eeaf7e4ea1ed8a108e1f2d0966ae4071198001e8480fd1ef328a17a8e8eeaf7e4ea1ed8a108e1f2d0960000000000000000000000000000000000000000000000023809c40b734007e2ba2ae424d960c26247dd6c32edc70b295c744c430c20ba2ae424d960c26247dd6c32edc70b295c744c431ef315fa08e0e1b116d97e3dfe0af292ed8b7f026ae4071198001e84801ef315fa08e0e1b116d97e3dfe0af292ed8b7f020000000000000000000000000000000000000000000000052bb156dd1f4a6cc2ba2ae424d960c26247dd6c32edc70b295c744c430c20ba2ae424d960c26247dd6c32edc70b295c744c43ac109c8025f272414fd9e2faa805a583708a017f6ae4071198002625a0ac109c8025f272414fd9e2faa805a583708a017f000000000000000000000000000000000000000000000026b7b5c03e337cced3ba2ae424d960c26247dd6c32edc70b295c744c4300a0c9e75c480000000000001c1302010000000000000000000000000000000000000001940001450000ca00007b0c20bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095ca527a61703d82139f8a06bc30097cc9caa2df5a66ae4071118001e8480a527a61703d82139f8a06bc30097cc9caa2df5a600000000000000000000000000000000000000000000011e1a8ba4cd0b30e9d8bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c02a000000000000000000000000000000000000000000000023ca26678b61174b518ee63c1e500afb2da14056725e3ba3a30dd846b6bbbd7886c56bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c0c20bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c0ed7e52944161450477ee417de9cd3a859b14fd06ae4071118002625a00ed7e52944161450477ee417de9cd3a859b14fd0000000000000000000000000000000000000000000001546f6e2fc0c390887d1bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c02a0000000000000000000000000000000000000000000001f5bc5d1f44db84eb8b8ee63c1e500133b3d95bad5405d14d53473671200e9342896bfbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c00a0f2fa6b660e09fabb73bd3ade0a17ecc321fd13a19e81ce82000000000000000000000000000000000000000000003dea76269337e03178ad0000000000000000256279c26ac6427d80a06c4eca270e09fabb73bd3ade0a17ecc321fd13a19e81ce82111111125421ca6dc452d289314280a0f8842a65000000000000000000000000b3276493";

  bytes public swapNativeSrcTokenData =
    hex"07ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000e09fabb73bd3ade0a17ecc321fd13a19e81ce82000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd09000000000000000000000000f4903f4544558515b26ec4c6d6e91d2293b272750000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000010af4365856885aef20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000ff0000000000000000000000000000000000000000e10000b300006900001a4041bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095cd0e30db002a0000000000000000000000000000000000000000000000010af4365856885aef2ee63c1e500afb2da14056725e3ba3a30dd846b6bbbd7886c56bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c00a0f2fa6b660e09fabb73bd3ade0a17ecc321fd13a19e81ce82000000000000000000000000000000000000000000000010da6847842b8472a7000000000000000024a160efce20206f80a06c4eca270e09fabb73bd3ade0a17ecc321fd13a19e81ce82111111125421ca6dc452d289314280a0f8842a6500b3276493";

  function setUp() public {
    // fork mainnet
    vm.createSelectFork("https://rpc.ankr.com/bsc", 43041807);

    vm.startPrank(user1);

    // deploy buyback with user1
    address buybackProxy = Upgrades.deployUUPSProxy(
      "Buyback.sol",
      abi.encodeCall(
        Buyback.initialize,
        (admin, manager, pauser, address(swapDstToken), address(receiver), address(oneInchRouter), swapNativeSrcToken)
      )
    );
    buyback = Buyback(payable(buybackProxy));
    console.log("buyback proxy address: %s", buybackProxy);
    vm.stopPrank();

    //grant access
    vm.startPrank(admin);
    buyback.grantRole(buyback.BOT(), bot);
    vm.stopPrank();

    // add swapSrcToken
    vm.startPrank(manager);
    deal(swapSrcToken, buybackProxy, 10000 ether);
    deal(buybackProxy, 10000 ether);

    buyback.addSwapSrcTokenWhitelist(swapNativeSrcToken);
    assertEq(buyback.swapSrcTokenWhitelist(swapNativeSrcToken), true);

    buyback.addSwapSrcTokenWhitelist(swapSrcToken);
    assertEq(buyback.swapSrcTokenWhitelist(swapSrcToken), true);
    vm.stopPrank();
  }

  /**
   * @dev test buyback
   */
  function testBuybackFail() public {
    //user no access
    vm.expectRevert();
    buyback.buyback(oneInchRouter, "");

    //pause contract
    vm.startPrank(admin);
    buyback.grantRole(buyback.PAUSER(), pauser);
    vm.stopPrank();
    vm.startPrank(pauser);
    if (buyback.paused() != true) {
      buyback.pause();
    }
    assertEq(buyback.paused(), true);
    vm.stopPrank();

    //contract not pause
    vm.startPrank(manager);
    if (buyback.paused() == true) {
      buyback.unpause();
    }
    assertEq(buyback.paused(), false);
    vm.stopPrank();

    vm.startPrank(bot);
    vm.expectRevert();
    buyback.buyback(oneInchRouter, "");
    vm.stopPrank();
  }

  /**
   * @dev test buyback
   */
  function testBuybackSuccess() public {
    //contract no pause
    vm.startPrank(admin);
    if (buyback.paused() == true) {
      buyback.unpause();
      assertEq(buyback.paused(), false);
    }
    vm.stopPrank();

    vm.startPrank(bot);
    uint256 beforeTotalBought = buyback.totalBought();
    uint256 beforeReceiverBalance = IERC20(swapDstToken).balanceOf(receiver);
    uint256 beforeBuybackBalance = IERC20(swapSrcToken).balanceOf(address(buyback));
    uint256 today = (block.timestamp / 1 days) * 1 days;
    uint256 beforeDailyBought = buyback.dailyBought(today);

    buyback.buyback(oneInchRouter, swapData);

    (, IBuyback.SwapDescription memory swapDesc, ) = abi.decode(
      sliceBytes(swapData, 4, swapData.length - 4),
      (address, IBuyback.SwapDescription, bytes)
    );

    uint256 afterTotalBought = buyback.totalBought();
    uint256 afterReceiverBalance = IERC20(swapDstToken).balanceOf(receiver);
    uint256 afterBuybackBalance = IERC20(swapSrcToken).balanceOf(address(buyback));
    uint256 afterDailyBought = buyback.dailyBought(today);

    uint256 diffTotalBought = afterTotalBought - beforeTotalBought;
    uint256 diffReceiverBalance = afterReceiverBalance - beforeReceiverBalance;
    uint256 diffBuybackBalance = beforeBuybackBalance - afterBuybackBalance;
    uint256 diffDailyBought = afterDailyBought - beforeDailyBought;

    assertEq(diffTotalBought, diffReceiverBalance);
    assertEq(diffDailyBought, diffReceiverBalance);
    assertEq(diffBuybackBalance, swapDesc.amount);
    assertGe(diffReceiverBalance, swapDesc.minReturnAmount);

    vm.stopPrank();
  }

  /**
   * @dev test buyback
   */
  function testBuybackSuccess_NativeSrcToken() public {
    //contract no pause
    vm.startPrank(admin);
    if (buyback.paused() == true) {
      buyback.unpause();
      assertEq(buyback.paused(), false);
    }
    vm.stopPrank();

    vm.startPrank(bot);
    uint256 beforeTotalBought = buyback.totalBought();
    uint256 beforeReceiverBalance = IERC20(swapDstToken).balanceOf(receiver);
    uint256 beforeBuybackBalance = address(buyback).balance;
    uint256 today = (block.timestamp / 1 days) * 1 days;
    uint256 beforeDailyBought = buyback.dailyBought(today);

    buyback.buyback(oneInchRouter, swapNativeSrcTokenData);

    (, IBuyback.SwapDescription memory swapDesc, ) = abi.decode(
      sliceBytes(swapNativeSrcTokenData, 4, swapNativeSrcTokenData.length - 4),
      (address, IBuyback.SwapDescription, bytes)
    );

    uint256 afterTotalBought = buyback.totalBought();
    uint256 afterReceiverBalance = IERC20(swapDstToken).balanceOf(receiver);
    uint256 afterBuybackBalance = address(buyback).balance;
    uint256 afterDailyBought = buyback.dailyBought(today);

    uint256 diffTotalBought = afterTotalBought - beforeTotalBought;
    uint256 diffReceiverBalance = afterReceiverBalance - beforeReceiverBalance;
    uint256 diffBuybackBalance = beforeBuybackBalance - afterBuybackBalance;
    uint256 diffDailyBought = afterDailyBought - beforeDailyBought;

    assertEq(diffTotalBought, diffReceiverBalance);
    assertEq(diffDailyBought, diffReceiverBalance);
    assertEq(diffBuybackBalance, swapDesc.amount);
    assertGe(diffReceiverBalance, swapDesc.minReturnAmount);

    vm.stopPrank();
  }

  /**
   * @dev test changeReceiver
   */
  function testChangeReceiver() public {
    address swapReceiver = makeAddr("receiver");
    //user no access
    vm.expectRevert();
    buyback.changeReceiver(swapReceiver);

    //zero address
    vm.startPrank(manager);
    vm.expectRevert("_receiver is the zero address");
    buyback.changeReceiver(address(0));
    vm.stopPrank();

    //change success
    vm.startPrank(manager);
    buyback.changeReceiver(swapReceiver);
    assertEq(buyback.receiver(), swapReceiver);
    vm.stopPrank();

    //duplicate change
    vm.startPrank(manager);
    assertEq(buyback.receiver(), swapReceiver);
    vm.expectRevert("_receiver is the same");
    buyback.changeReceiver(swapReceiver);
    vm.stopPrank();
  }

  /**
   * @dev test changeSwapNativeAddress
   */
  function testChangeSwapNativeAddress() public {
    address swapNativeAddress = makeAddr("swapNativeAddress");
    //user no access
    vm.expectRevert();
    buyback.changeSwapNativeAddress(swapNativeAddress);

    //zero address
    vm.startPrank(manager);
    vm.expectRevert("_swapNativeAddress is the zero address");
    buyback.changeSwapNativeAddress(address(0));
    vm.stopPrank();

    //change success
    vm.startPrank(manager);
    buyback.changeSwapNativeAddress(swapNativeAddress);
    assertEq(buyback.swapNativeAddress(), swapNativeAddress);
    vm.stopPrank();

    //duplicate change
    vm.startPrank(manager);
    assertEq(buyback.swapNativeAddress(), swapNativeAddress);
    vm.expectRevert("_swapNativeAddress is the same");
    buyback.changeSwapNativeAddress(swapNativeAddress);
    vm.stopPrank();
  }

  /**
   * @dev test Add1InchRouterWhitelist
   */
  function testAdd1InchRouterWhitelist() public {
    address router = makeAddr("oneInchRouter");
    //user no access
    vm.expectRevert();
    buyback.add1InchRouterWhitelist(router);

    //add success
    vm.startPrank(manager);
    buyback.add1InchRouterWhitelist(router);
    assertEq(buyback.oneInchRouterWhitelist(router), true);
    vm.stopPrank();

    //duplicate add
    vm.startPrank(manager);
    assertEq(buyback.oneInchRouterWhitelist(router), true);
    vm.expectRevert("oneInchRouter already whitelisted");
    buyback.add1InchRouterWhitelist(router);
    vm.stopPrank();
  }

  /**
   * @dev test Remove1InchRouterWhitelist
   */
  function testRemove1InchRouterWhitelist() public {
    address router = makeAddr("oneInchRouter");
    //user no access
    vm.expectRevert();
    buyback.remove1InchRouterWhitelist(router);

    //no oneInchRouter in whitelisted
    vm.startPrank(manager);
    assertEq(buyback.oneInchRouterWhitelist(router), false);
    vm.expectRevert("oneInchRouter not whitelisted");
    buyback.remove1InchRouterWhitelist(router);
    vm.stopPrank();

    //remove success
    vm.startPrank(manager);
    buyback.add1InchRouterWhitelist(router);
    assertEq(buyback.oneInchRouterWhitelist(router), true);
    buyback.remove1InchRouterWhitelist(router);
    assertEq(buyback.oneInchRouterWhitelist(router), false);
    vm.stopPrank();
  }

  /**
   * @dev test AddSwapSrcTokenWhitelist
   */
  function testAddSwapSrcTokenWhitelist() public {
    address srcToken = makeAddr("srcToken1");
    //user no access
    vm.expectRevert();
    buyback.addSwapSrcTokenWhitelist(srcToken);

    //add success
    vm.startPrank(manager);
    buyback.addSwapSrcTokenWhitelist(srcToken);
    assertEq(buyback.swapSrcTokenWhitelist(srcToken), true);
    vm.stopPrank();

    //duplicate add
    vm.startPrank(manager);
    assertEq(buyback.swapSrcTokenWhitelist(srcToken), true);
    vm.expectRevert("srcToken already whitelisted");
    buyback.addSwapSrcTokenWhitelist(srcToken);
    vm.stopPrank();
  }

  /**
   * @dev test RemoveSwapSrcTokenWhitelist
   */
  function testRemoveSwapSrcTokenWhitelist() public {
    address srcToken = makeAddr("srcToken1");
    //user no access
    vm.expectRevert();
    buyback.removeSwapSrcTokenWhitelist(srcToken);

    //no srcToken in whitelisted
    vm.startPrank(manager);
    assertEq(buyback.swapSrcTokenWhitelist(srcToken), false);
    vm.expectRevert("srcToken not whitelisted");
    buyback.removeSwapSrcTokenWhitelist(srcToken);
    vm.stopPrank();

    //remove success
    vm.startPrank(manager);
    buyback.addSwapSrcTokenWhitelist(srcToken);
    assertEq(buyback.swapSrcTokenWhitelist(srcToken), true);
    buyback.removeSwapSrcTokenWhitelist(srcToken);
    assertEq(buyback.swapSrcTokenWhitelist(srcToken), false);
    vm.stopPrank();
  }

  /**
   * @dev test pause the contract
   */
  function testPauseAndUnpause() public {
    //grant pauser access
    vm.startPrank(admin);
    buyback.grantRole(buyback.PAUSER(), pauser);
    vm.stopPrank();

    vm.startPrank(pauser);
    buyback.pause();
    assertEq(buyback.paused(), true);
    vm.stopPrank();

    //grant access
    vm.startPrank(manager);
    buyback.unpause();
    assertEq(buyback.paused(), false);
    vm.stopPrank();
  }

  function testReceiveBNB() public {
    address userBNB = makeAddr("userBNB");
    deal(userBNB, 1 ether);

    vm.startPrank(userBNB);
    uint256 balanceBefore = address(buyback).balance;
    console.log("balanceBefore=%s", balanceBefore);

    payable(buyback).sendValue(1 ether);
    console.log("balanceAfter=%s", address(buyback).balance);
    assertEq(address(buyback).balance, balanceBefore + 1 ether);
    assertEq(userBNB.balance, 0 ether);

    vm.stopPrank();
  }

  /**
   * @dev test upgrade
   */
  function testUpgrade() public {
    address proxyAddress = address(buyback);
    address implAddressV1 = Upgrades.getImplementationAddress(proxyAddress);

    //no access
    vm.expectRevert();
    Upgrades.upgradeProxy(proxyAddress, "Buyback.sol", "", msg.sender);

    //upgradeProxy success
    vm.startPrank(admin);
    Upgrades.upgradeProxy(proxyAddress, "Buyback.sol", "", msg.sender);
    address implAddressV2 = Upgrades.getImplementationAddress(proxyAddress);
    assertFalse(implAddressV2 == implAddressV1);
    vm.stopPrank();
    console.log("implAddressV1: %s", implAddressV1);
    console.log("implAddressV2: %s", implAddressV2);
  }

  function sliceBytes(bytes memory data, uint start, uint length) public pure returns (bytes memory) {
    require(data.length >= start + length, "Out of bounds");
    bytes memory result = new bytes(length);
    for (uint i = 0; i < length; i++) {
      result[i] = data[start + i];
    }
    return result;
  }
}
