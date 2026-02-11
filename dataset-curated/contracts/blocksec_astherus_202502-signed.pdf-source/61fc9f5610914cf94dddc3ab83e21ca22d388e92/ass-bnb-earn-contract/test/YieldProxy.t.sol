// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { AsBnbMinter } from "../src/AsBnbMinter.sol";
import { IAsBnbMinter } from "../src/interfaces/IAsBnbMinter.sol";
import { YieldProxy } from "../src/YieldProxy.sol";
import { IYieldProxy } from "../src/interfaces/IYieldProxy.sol";
import { AsBNB } from "../src/AsBNB.sol";
import { MockERC20 } from "../src/mock/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IListaStakeManager } from "../src/interfaces/IListaStakeManager.sol";
import { ISlisBNBProvider } from "../src/interfaces/ISlisBNBProvider.sol";

// Run this command to test
// forge clean && forge build && forge test -vvv --match-contract YieldProxyTest
// if you want to run specific test, you can add `--match-function flag` as well

contract YieldProxyTest is Test {
  using SafeERC20 for IERC20;
  using SafeERC20 for AsBNB;

  address admin = makeAddr("ADMIN");
  address manager = makeAddr("MANAGER");
  address pauser = makeAddr("PAUSER");
  address bot = makeAddr("BOT");
  address user = makeAddr("USER");
  address rewardSender = makeAddr("REWARD_SENDER");
  address feeReceiver = makeAddr("FEE_RECEIVER");
  address fatFinger = makeAddr("FAT_FINGER");
  address MPCWallet = makeAddr("MPC_WALLET");

  YieldProxy yieldProxy;
  AsBnbMinter minter;
  AsBNB asBNB;

  // slisBNB
  IERC20 token = IERC20(0xCc752dC4ae72386986d011c2B485be0DAd98C744);
  // StakeManager - BNB <> slisBNB
  IListaStakeManager listaStakeManager = IListaStakeManager(0xc695F964011a5a1024931E2AF0116afBaC41B31B);
  // slisBNBProvider - slisBNB <> clisBNB
  ISlisBNBProvider slisBNBProvider = ISlisBNBProvider(0x11f6aDcb73473FD7bdd15f32df65Fa3ECdD0Bc20);

  function setUp() public {
    // fork testnet
    string memory url = vm.envString("TESTNET_RPC");
    vm.createSelectFork(url);

    // deploy AsBNB
    asBNB = new AsBNB("Astherus BNB", "asBNB", admin, admin);

    // deploy yieldProxy
    address ypProxy = Upgrades.deployUUPSProxy(
      "YieldProxy.sol",
      abi.encodeCall(
        YieldProxy.initialize,
        (admin, manager, pauser, bot, address(token), address(asBNB), address(listaStakeManager), admin)
      )
    );
    yieldProxy = YieldProxy(payable(ypProxy));

    // deploy minter
    address minterProxy = Upgrades.deployUUPSProxy(
      "AsBnbMinter.sol",
      abi.encodeCall(AsBnbMinter.initialize, (admin, manager, pauser, bot, address(token), address(asBNB), ypProxy))
    );
    minter = AsBnbMinter(minterProxy);

    // set roles
    vm.startPrank(admin);
    asBNB.setMinter(address(minter));
    vm.stopPrank();

    vm.startPrank(manager);
    yieldProxy.setMinter(address(minter));
    yieldProxy.setSlisBNBProvider(address(slisBNBProvider));
    yieldProxy.setMPCWallet(MPCWallet);
    yieldProxy.setRewardsSender(rewardSender);
    vm.stopPrank();

    // give all roles some BNB
    deal(admin, 100000 ether);
    deal(manager, 100000 ether);
    deal(pauser, 100000 ether);
    deal(bot, 100000 ether);
    deal(user, 100000 ether);
    deal(rewardSender, 100000 ether);
  }

  /**
   * @dev compound rewards from yield proxy
   */
  function test_compound_rewards() public {
    // set a 10% fee rate
    vm.prank(manager);
    minter.setFeeRate(1000); // 1000/10000

    // add 2 activities
    vm.startPrank(manager);
    yieldProxy.addActivity(block.timestamp + 1000, block.timestamp + 2000, "TestToken1");
    yieldProxy.addActivity(block.timestamp + 1000, block.timestamp + 3000, "TestToken2");
    yieldProxy.addActivity(block.timestamp + 1000, block.timestamp + 4000, "TestToken3");
    vm.stopPrank();

    // activity started
    skip(1001);

    // launchpool rewards 5000 BNB
    vm.prank(rewardSender);
    (bool success, ) = address(yieldProxy).call{ value: 5000 ether }("");
    assertEq(success, true);

    uint256 totalTokens_1 = minter.totalTokens();
    uint256 netFee_1 = minter.feeAvailable();
    console.log("totalTokens_1: %s", totalTokens_1);
    console.log("netFee_1: %s", netFee_1);

    // compoundRewards
    vm.prank(bot);
    yieldProxy.settleActivity();

    uint256 totalTokens_2 = minter.totalTokens();
    uint256 netFee_2 = minter.feeAvailable();
    assertGt(totalTokens_2, totalTokens_1);
    assertGt(netFee_2, netFee_1);
    console.log("totalTokens_2: %s", totalTokens_2);
    console.log("netFee_2: %s", netFee_2);

    // at this point all rewards has been converted to slisBNB and compounded
    vm.prank(bot);
    vm.expectRevert("No rewards to compound");
    yieldProxy.settleActivity();

    // another rewards for activity 2 comes in
    vm.prank(rewardSender);
    (success, ) = address(yieldProxy).call{ value: 5000 ether }("");
    assertEq(success, true);

    // compoundRewards
    vm.prank(bot);
    yieldProxy.settleActivity();

    uint256 totalTokens_3 = minter.totalTokens();
    uint256 netFee_3 = minter.feeAvailable();
    assertGt(totalTokens_3, totalTokens_2);
    assertGt(netFee_3, netFee_2);
    console.log("totalTokens_3: %s", totalTokens_3);
    console.log("netFee_3: %s", netFee_3);

    // at this point, there are only 1 active activity
    // but try to end 5 more and endActivity() shall able to handle it
    vm.prank(manager);
    yieldProxy.endActivity(5);

    // no more activities to settle
    vm.prank(bot);
    vm.expectRevert("No active activity");
    yieldProxy.settleActivity();

    // add one more activity
    vm.prank(manager);
    yieldProxy.addActivity(block.timestamp + 1000, block.timestamp + 5000, "TestToken4");

    skip(1001);

    // should trigger to the first assert
    vm.prank(bot);
    vm.expectRevert("No rewards to compound");
    yieldProxy.settleActivity();

    // end the last activity
    vm.prank(manager);
    yieldProxy.endActivity(1);
  }

  /**
   * @dev test pause and unpause function
   */
  function test_pause_and_unpause() public {
    // pause and unpause with no access
    vm.expectRevert();
    yieldProxy.unpause();

    vm.expectRevert();
    yieldProxy.pause();

    // pause contract
    vm.startPrank(pauser);
    yieldProxy.pause();
    assertEq(yieldProxy.paused(), true);
    vm.stopPrank();

    // unpause contract
    vm.startPrank(manager);
    yieldProxy.unpause();
    assertEq(yieldProxy.paused(), false);
    vm.stopPrank();
  }

  /**
   * @dev test admin withdraw native token
   *      if someone(not Lista rewards sender) sends BNB to the contract,
   *      admin has the right to withdraw it and send it back to the original sender
   */
  function test_withdraw_native_token() public {
    deal(fatFinger, 1000 ether);

    // fat finger sends 1000 BNB to the yield proxy
    vm.prank(fatFinger);
    (bool success, ) = address(yieldProxy).call{ value: 1000 ether }("");
    assertEq(success, true);
    assertEq(address(yieldProxy).balance, 1000 ether);
    assertEq(fatFinger.balance, 0);

    uint256 postBalance = manager.balance;
    // manager withdraws the BNB to himself
    vm.startPrank(manager);
    yieldProxy.withdrawNativeToken(1000 ether);
    assertEq(address(yieldProxy).balance, 0);
    assertEq(manager.balance, postBalance + 1000 ether);

    // then manager transfer the BNB back to fat finger
    (bool success2, ) = fatFinger.call{ value: 1000 ether }("");
    assertEq(success2, true);
    assertEq(fatFinger.balance, 1000 ether);
    vm.stopPrank();
  }

  /**
   * @dev test upgrade
   */
  function test_upgrade() public {
    address proxyAddress = address(yieldProxy);
    address implAddressV1 = Upgrades.getImplementationAddress(proxyAddress);

    vm.expectRevert();
    Upgrades.upgradeProxy(proxyAddress, "YieldProxy.sol", "", msg.sender);

    vm.startPrank(admin);
    Upgrades.upgradeProxy(proxyAddress, "YieldProxy.sol", "", msg.sender);
    address implAddressV2 = Upgrades.getImplementationAddress(proxyAddress);
    assertFalse(implAddressV2 == implAddressV1);
    vm.stopPrank();
    console.log("implAddressV1: %s", implAddressV1);
    console.log("implAddressV2: %s", implAddressV2);
  }
}
